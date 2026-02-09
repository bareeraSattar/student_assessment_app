import 'package:flutter/material.dart';
import 'api_service.dart';
import 'models.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';

class AssessmentScreen extends StatefulWidget {
  final Subject subject;

  const AssessmentScreen({super.key, required this.subject});

  @override
  State<AssessmentScreen> createState() => _AssessmentScreenState();
}

class _AssessmentScreenState extends State<AssessmentScreen> {
  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  List<Criteria> _criteria = [];
  Student? _selectedStudent;
  Map<int, double> _criteriaScores = {};
  int? _existingAssessmentId;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String _error = '';
  bool _isOffline = false;

  int? _currentUserId;
  String? _currentUserRollNo;
  bool _isAdmin = false;

  final TextEditingController _searchController = TextEditingController();

  static const List<Color> _accentColors = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF472B6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF14B8A6),
    Color(0xFFD97706),
  ];

  Color get _accentColor => _accentColors[widget.subject.id % _accentColors.length];

  @override
  void initState() {
    super.initState();
    _checkOfflineStatus();
    _loadCurrentUser();
    _loadInitialData();
  }

  Future<void> _checkOfflineStatus() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      _isOffline = connectivityResult == ConnectivityResult.none;
    });
  }

  Future<void> _loadCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('current_user');
    if (userJson != null) {
      try {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        setState(() {
          _currentUserId = int.tryParse(userMap['id']?.toString() ?? '0');
          _currentUserRollNo = userMap['roll_number']?.toString();
          _isAdmin = userMap['is_admin'] == 1;
        });
      } catch (e) {
        print('Failed to load current user: $e');
      }
    }
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final students = await ApiService.getStudents();
      final criteria = await ApiService.getCriteria(
        widget.subject.id,
        type: 'assessment',
      );

      setState(() {
        _students = students;
        _filteredStudents = students;
        _criteria = criteria;
        _criteriaScores.clear();
        for (var c in _criteria) {
          _criteriaScores[c.id] = 0.0;
        }
        _isLoading = false;
      });

      await _autoSelectMe();
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('No internet') && errorMsg.contains('cached criteria')) {
        setState(() {
          _error = '';
          _isLoading = false;
        });
      } else if (errorMsg.contains('No internet') || _isOffline) {
        setState(() {
          _error = 'Offline Mode – Showing last saved criteria';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load data: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _autoSelectMe() async {
    if (_currentUserRollNo == null || _students.isEmpty) return;

    final me = _students.firstWhere(
      (s) => s.rollNo == _currentUserRollNo,
      orElse: () => _students[0],
    );

    setState(() {
      _selectedStudent = me;
    });

    await _checkAndPreFill(me.id);
  }

  bool get _isSelfAssessment => _selectedStudent != null && _selectedStudent!.rollNo == _currentUserRollNo;

  Future<void> _checkAndPreFill(int studentId) async {
    try {
      final previous = await ApiService.getPreviousAssessmentForStudent(
        subjectId: widget.subject.id,
        studentId: studentId,
      );

      setState(() {
        if (previous != null && previous.criteriaScores.isNotEmpty) {
          _existingAssessmentId = previous.id;

          // Apply previous scores using criteriaId matching
          for (var c in _criteria) {
            final prevScore = previous.criteriaScores.firstWhere(
              (s) => s.criteriaId == c.id,
              orElse: () => CriteriaScore(
                criteriaId: c.id,
                name: c.name,
                obtained: 0.0,
                max: c.maxMarks,
              ),
            );

            _criteriaScores[c.id] = prevScore.obtained;
          }

          debugPrint('Pre-filled ${_criteriaScores.length} criteria from previous assessment #${previous.id}');
          debugPrint('Pre-filled scores:');
          _criteriaScores.forEach((id, value) {
            debugPrint('  → Criteria ID $id: $value');
          });
        } else {
          _existingAssessmentId = null;

          // Reset sliders to zero if no previous data
          for (var c in _criteria) {
            _criteriaScores[c.id] = 0.0;
          }

          debugPrint('No previous assessment found or no scores → sliders reset to 0');
        }
      });
    } catch (e) {
      debugPrint('Failed to pre-fill previous scores: $e');
      if (!_isOffline && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load previous marks: $e')),
        );
      }
      // Reset to zero on error
      setState(() {
        for (var c in _criteria) {
          _criteriaScores[c.id] = 0.0;
        }
      });
    }
  }

  double _calculateTotal() {
    double total = 0;
    for (var c in _criteria) {
      total += _criteriaScores[c.id] ?? 0;
    }
    return total;
  }

  double _calculateMaxPossible() {
    double total = 0;
    for (var c in _criteria) {
      total += c.maxMarks;
    }
    return total;
  }

  Future<void> _submitAssessment() async {
    if (_selectedStudent == null || _selectedStudent!.id == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid student')),
      );
      return;
    }

    if (_isSelfAssessment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot assess yourself')),
      );
      return;
    }

    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline Mode: Submission requires internet connection'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final criteriaScores = _criteria.map((c) {
      return {
        'criteria_id': c.id,
        'marks_awarded': _criteriaScores[c.id] ?? 0.0,
      };
    }).toList();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      setState(() => _isSubmitting = true);

      Map<String, dynamic> response;

      if (_existingAssessmentId != null) {
        response = await ApiService.updateAssessment(
          subjectId: widget.subject.id,
          assessmentData: {
            'assessment_id': _existingAssessmentId,
            'assessment_date': today,
            'criteria_scores': criteriaScores,
          },
        );
      } else {
        response = await ApiService.submitAssessment(
          studentId: _selectedStudent!.id,
          subjectId: widget.subject.id,
          assessmentDate: today,
          criteriaScores: criteriaScores,
        );
      }

      setState(() => _isSubmitting = false);

      if (response['status'] == 'success') {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Success'),
            content: Text(_existingAssessmentId != null
                ? 'Assessment updated successfully!'
                : 'Assessment submitted successfully!'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Submission failed')),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting assessment: $e')),
      );
    }
  }

  void _showStudentSelection() {
    _searchController.clear();

    // Filter out self for students (admins see everyone)
    List<Student> selectableStudents = _students;
    if (!_isAdmin) {
      selectableStudents = _students.where((s) => s.rollNo != _currentUserRollNo).toList();
    }
    setState(() => _filteredStudents = selectableStudents);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Student'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or roll...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (query) {
                    setState(() {
                      final lowerQuery = query.toLowerCase();
                      _filteredStudents = selectableStudents.where((student) {
                        return student.name.toLowerCase().contains(lowerQuery) ||
                               student.rollNo.toLowerCase().contains(lowerQuery);
                      }).toList();
                    });
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredStudents.length,
                  itemBuilder: (context, index) {
                    final student = _filteredStudents[index];
                    final isMe = student.rollNo == _currentUserRollNo;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _accentColor.withOpacity(0.2),
                        child: Text(
                          student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                          style: TextStyle(color: _accentColor),
                        ),
                      ),
                      title: Text(
                        student.name + (isMe ? ' (Me)' : ''),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Roll: ${student.rollNo}'),
                          if (student.className != null) Text(student.className!),
                        ],
                      ),
                      onTap: () {
                        setState(() => _selectedStudent = student);
                        print('Selected student: ${student.name} (ID: ${student.id}, Roll: ${student.rollNo})');
                        _checkAndPreFill(student.id);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSelector() {
    return Card(
      elevation: Theme.of(context).brightness == Brightness.light ? 1.5 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Information',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            if (_selectedStudent == null)
              FilledButton.icon(
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Select Student'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: _showStudentSelection,
              )
            else
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _accentColor.withOpacity(0.15),
                    child: Text(
                      _selectedStudent!.name[0].toUpperCase(),
                      style: TextStyle(fontSize: 24, color: _accentColor),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedStudent!.name + (_isSelfAssessment ? ' (Me)' : ''),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text('Roll: ${_selectedStudent!.rollNo}'),
                        if (_selectedStudent!.className != null)
                          Text(
                            _selectedStudent!.className!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: _accentColor),
                    onPressed: _showStudentSelection,
                  ),
                ],
              ),
            if (_isSelfAssessment)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Note: You cannot assess yourself',
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                ),
              ),
            if (_isOffline || _error.contains('Offline Mode'))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Offline Mode – Viewing last saved criteria',
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriteriaList() {
  return Card(
    elevation: Theme.of(context).brightness == Brightness.light ? 1.5 : 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assessment Criteria',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          ..._criteria.asMap().entries.map((entry) {
            final idx = entry.key;
            final criteriaItem = entry.value;
            final score = _criteriaScores[criteriaItem.id] ?? 0.0;
            final accent = _accentColors[idx % _accentColors.length];

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          criteriaItem.name,  // ← Criteria name restored
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        'Max: ${criteriaItem.maxMarks.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: accent,                    // ← Color restored
                      activeTrackColor: accent,              // ← Active color restored
                      inactiveTrackColor: accent.withOpacity(0.2),
                      trackHeight: 8,
                      overlayColor: accent.withOpacity(0.2),
                      valueIndicatorColor: accent,
                      valueIndicatorShape: const RectangularSliderValueIndicatorShape(),
                      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                      showValueIndicator: ShowValueIndicator.always,
                    ),
                    child: Slider(
                      key: Key('slider_${criteriaItem.id}_${score}'), // Forces rebuild when score changes
                      value: score,
                      min: 0,
                      max: criteriaItem.maxMarks,
                      divisions: (criteriaItem.maxMarks * 2).toInt(),
                      label: score.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() {
                          _criteriaScores[criteriaItem.id] = value;
                        });
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0', style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        'Score: ${score.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: accent,  // ← Score color restored
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        criteriaItem.maxMarks.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    ),
  );
}

  Widget _buildSummary() {
    final total = _calculateTotal();
    final maxPossible = _calculateMaxPossible();
    final percentage = maxPossible > 0 ? (total / maxPossible * 100) : 0.0;

    return Card(
      elevation: Theme.of(context).brightness == Brightness.light ? 1.5 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assessment Summary',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _buildSummaryRow('Total Marks', total.toStringAsFixed(1), _accentColor),
            const SizedBox(height: 8),
            _buildSummaryRow('Max Possible', maxPossible.toStringAsFixed(1), null),
            const SizedBox(height: 8),
            _buildSummaryRow(
              'Percentage',
              '${percentage.toStringAsFixed(1)}%',
              percentage >= 50 ? Colors.green : Colors.red,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, Color? color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: color ?? Theme.of(context).colorScheme.onSurface,
              ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_accentColor)),
          const SizedBox(height: 24),
          Text(
            'Loading assessment data...',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 72, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _error,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: _accentColor),
              onPressed: _loadInitialData,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject.name} - Assessment'),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildLoading()
          : _error.isNotEmpty && !_error.contains('Offline Mode')
              ? _buildError()
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Column(
                      children: [
                        _buildStudentSelector(),
                        const SizedBox(height: 16),
                        _buildCriteriaList(),
                        const SizedBox(height: 16),
                        _buildSummary(),
                        const SizedBox(height: 32),
                        FilledButton.icon(
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.send),
                          label: Text(_isSubmitting ? 'Submitting...' : 'Submit Assessment'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _accentColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          onPressed: _isSubmitting ? null : _submitAssessment,
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}