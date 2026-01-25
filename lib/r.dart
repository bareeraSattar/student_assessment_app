import 'package:flutter/material.dart';
import 'api_service.dart';
import 'models.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your chat screen (create if not done)
import 'ai_chat_screen.dart';

class RecordsScreen extends StatefulWidget {
  final Subject subject;
  final Student? currentStudent;
  const RecordsScreen({
    super.key,
    required this.subject,
    this.currentStudent,
  });

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  int _currentIndex = 0;
  List<Assessment> _givenAssessments = [];
  List<Assessment> _receivedAssessments = [];
  List<Assessment> _allAssessments = [];
  List<Assessment> _adminProvided = [];
  List<Assessment> _studentPeerAssessments = [];
  List<Student> _allStudents = [];
  List<User> _allUsers = [];
  double? _averagePercentage;
  bool _isAdmin = false;
  bool _isLoading = true;
  String _error = '';
  bool _isOffline = false;
  bool _hasShownOfflineNotice = false;
  final TextEditingController _feedbackController = TextEditingController();
  int? _selectedAssessmentId;

  String? _aiFeedback;
  bool _isFetchingAI = false;
  String? _aiError;

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
  static const List<Color> _criteriaColors = [
    Color(0xFF8B5CF6),
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFFEC4899),
    Color(0xFF6366F1),
    Color(0xFF14B8A6),
  ];

  @override
  void initState() {
    super.initState();
    _loadCachedDataImmediately();
  }

  Future<void> _loadCachedDataImmediately() async {
    final loaded = await _loadFromCache();
    if (loaded) {
      setState(() {
        _isLoading = false;
      });
    }
    await _checkOfflineStatus();
    await _loadUserRoleAndData();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _checkOfflineStatus() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult != ConnectivityResult.none;
      setState(() {
        _isOffline = !isConnected;
      });
      debugPrint('Connectivity check: $connectivityResult | isOffline: $_isOffline');
    } catch (e) {
      debugPrint('Connectivity error: $e');
      setState(() => _isOffline = true);
    }
  }

  Future<void> _saveStudentRecords() async {
    if (_isAdmin || (_givenAssessments.isEmpty && _receivedAssessments.isEmpty)) {
      debugPrint("No new data to save → skipping cache");
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'records_subject_${widget.subject.id}';
      final receivedJson = _receivedAssessments.map((a) => a.toJson()).toList();
      final givenJson = _givenAssessments.map((a) => a.toJson()).toList();
      final data = {
        'received': receivedJson,
        'given': givenJson,
        'average': _averagePercentage,
        'timestamp': DateTime.now().toIso8601String(),
      };
      await prefs.setString(key, jsonEncode(data));
      debugPrint('CACHE SAVED SUCCESSFULLY for subject ${widget.subject.id}');
      debugPrint(' → given: ${_givenAssessments.length}');
      debugPrint(' → received: ${_receivedAssessments.length}');
      debugPrint(' → average: $_averagePercentage');
    } catch (e) {
      debugPrint('CACHE SAVE FAILED: $e');
    }
  }

  Future<bool> _loadFromCache() async {
    if (_isAdmin) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'records_subject_${widget.subject.id}';
      final jsonStr = prefs.getString(key);
      debugPrint("Cache string for key $key: $jsonStr");
      if (jsonStr == null || jsonStr.isEmpty) {
        debugPrint("No cache found for key: $key");
        return false;
      }
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final received = (data['received'] as List<dynamic>?)
              ?.map((e) {
                try {
                  return Assessment.fromJson(e as Map<String, dynamic>);
                } catch (err) {
                  debugPrint('Cache received parse error: $err');
                  return null;
                }
              })
              .whereType<Assessment>()
              .toList() ??
          [];
      final given = (data['given'] as List<dynamic>?)
              ?.map((e) {
                try {
                  return Assessment.fromJson(e as Map<String, dynamic>);
                } catch (err) {
                  debugPrint('Cache given parse error: $err');
                  return null;
                }
              })
              .whereType<Assessment>()
              .toList() ??
          [];
      final avg = double.tryParse(data['average']?.toString() ?? '0');
      setState(() {
        _receivedAssessments = received;
        _givenAssessments = given;
        _averagePercentage = avg;
      });
      debugPrint("CACHE LOADED → given: ${given.length}, received: ${received.length}, avg: $avg");
      return true;
    } catch (e) {
      debugPrint("CACHE LOAD ERROR: $e");
      return false;
    }
  }

  Future<void> _loadUserRoleAndData() async {
    final hasAnyDataAlready = _averagePercentage != null ||
        _givenAssessments.isNotEmpty ||
        _receivedAssessments.isNotEmpty;
    if (!hasAnyDataAlready) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }
    _isAdmin = await ApiService.isCurrentUserAdmin();
    bool success = false;
    if (!_isOffline) {
      try {
        final data = await ApiService.getAssessmentsForRecords(widget.subject.id);
        final currentUserId = await ApiService.getCurrentUserId() ?? 0;
        List<Assessment> newGiven = [];
        List<Assessment> newReceived = [];
        double? newAverage;
        if (_isAdmin) {
          _allAssessments = (data['all_assessments'] as List?)?.cast<Assessment>() ?? [];
          newGiven = _allAssessments.where((a) => a.assessorId == currentUserId).toList();
        } else {
          newGiven = (data['given'] as List?)?.cast<Assessment>() ?? [];
          newReceived = (data['received'] as List?)?.cast<Assessment>() ?? [];
          newAverage = double.tryParse(data['average_percentage']?.toString() ?? '0');
        }
        setState(() {
          if (_isAdmin) {
            _adminProvided = newGiven;
            _studentPeerAssessments = _allAssessments.where((a) => a.assessorId != currentUserId).toList();
          } else {
            _givenAssessments = newGiven;
            _receivedAssessments = newReceived;
            _averagePercentage = newAverage;
          }
        });
        debugPrint('Loaded assessments → given: ${newGiven.length}, received: ${newReceived.length}, all: ${_allAssessments.length}');
        if (!_isAdmin && (newGiven.isNotEmpty || newReceived.isNotEmpty || newAverage != null)) {
          await _saveStudentRecords();
        }
        success = true;
      } catch (e) {
        debugPrint('Online fetch failed: $e');
        _error = 'Failed to load from server: $e';
      }
    } else {
      debugPrint('Offline detected - skipping online fetch');
    }
    if (!success && !_isAdmin) {
      final loaded = await _loadFromCache();
      if (loaded) {
        success = true;
        if (!_hasShownOfflineNotice && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline mode — showing last saved data'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          _hasShownOfflineNotice = true;
        }
      }
    }
    setState(() {
      _isLoading = false;
      if (!success && !hasAnyDataAlready) {
        _error = _isOffline
            ? 'No saved records found for this subject yet.\nOpen once with internet connection.'
            : 'Failed to load records';
      } else {
        _error = '';
      }
    });
    if (_isAdmin) {
      try {
        final users = await _getAllUsers();
        setState(() => _allUsers = users);
      } catch (e) {
        debugPrint('Users fetch error: $e');
      }
    }
  }

  Future<List<User>> _getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/get_users.php?is_admin=1'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          final List<dynamic> list = data['users'] ?? [];
          return list.map((json) => User.fromJson(json)).toList();
        }
      }
    } catch (e) {
      debugPrint('Users fetch error: $e');
    }
    return [];
  }

  Future<void> _submitFeedback(int assessmentId) async {
    final feedbackText = _feedbackController.text.trim();
    if (feedbackText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter feedback')),
      );
      return;
    }
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline Mode: Feedback requires internet'), backgroundColor: Colors.orangeAccent),
      );
      return;
    }
    try {
      final response = await ApiService.submitFeedback(feedback: feedbackText, assessmentId: assessmentId);
      if (response['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Feedback submitted'), backgroundColor: Colors.green),
        );
        _feedbackController.clear();
        setState(() => _selectedAssessmentId = null);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to submit feedback')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showFeedbackDialog(Assessment assessment) {
    _selectedAssessmentId = assessment.id;
    _feedbackController.clear();
    final accent = _accentColors[assessment.id % _accentColors.length];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [Icon(Icons.feedback_outlined, color: accent), const SizedBox(width: 12), const Text('Add Feedback')],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: accent.withOpacity(0.15),
                  child: Text(
                    assessment.studentName.isNotEmpty ? assessment.studentName[0].toUpperCase() : '?',
                    style: TextStyle(color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        assessment.studentName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Text(
                        'Date: ${assessment.assessmentDate.split(' ').first}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _feedbackController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                labelText: 'Your Feedback',
                hintText: 'Enter detailed feedback here...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            if (_isOffline)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Offline Mode: Feedback requires internet',
                  style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            onPressed: _isOffline ? null : () { Navigator.pop(context); _submitFeedback(assessment.id); },
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 80) return Colors.green.shade700;
    if (percentage >= 60) return Colors.blue.shade700;
    if (percentage >= 40) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Widget _buildAssessmentCard(Assessment assessment, {bool isReceived = false, bool showAssessor = false}) {
    final accent = _accentColors[assessment.id % _accentColors.length];
    final percentColor = _getPercentageColor(assessment.percentage);
    return Card(
      elevation: Theme.of(context).brightness == Brightness.light ? 1.5 : 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accent.withOpacity(0.25), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16), // reduced padding to help with overflow
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: accent.withOpacity(0.15),
                          child: Text(
                            isReceived ? '?' : (assessment.studentName.isNotEmpty ? assessment.studentName[0].toUpperCase() : '?'),
                            style: TextStyle(fontSize: 20, color: accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isReceived ? 'Anonymous' : assessment.studentName,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Chip(
                    backgroundColor: percentColor.withOpacity(0.15),
                    label: Text(
                      '${assessment.percentage.toStringAsFixed(1)}%',
                      style: TextStyle(color: percentColor, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Date: ${assessment.assessmentDate.split(' ').first}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (showAssessor && assessment.assessorName != null && assessment.assessorName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Assessed by: ${assessment.assessorName}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Marks', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      Text(
                        '${assessment.totalMarks.toStringAsFixed(1)} / ${assessment.maxPossibleMarks.toStringAsFixed(1)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_comment_outlined, size: 20),
                    label: const Text('Add Feedback'),
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size(140, 40), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    onPressed: () => _showFeedbackDialog(assessment),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchAIFeedback() async {
    if (_isFetchingAI) return;

    setState(() {
      _isFetchingAI = true;
      _aiFeedback = null;
      _aiError = null;
    });

    try {
      final result = await ApiService.getAIFeedback(
        subjectId: widget.subject.id,
        subjectName: widget.subject.name,
      );

      setState(() {
        if (result['success'] == true) {
          _aiFeedback = result['feedback'] as String?;
          if (_aiFeedback == null || _aiFeedback!.trim().isEmpty) {
            _aiFeedback = "No detailed advice available right now. Please try again later.";
          }
        } else {
          _aiError = result['message'] as String? ?? 'Failed to get AI feedback';
        }
      });
    } catch (e) {
      setState(() {
        _aiError = 'Error connecting to AI service: $e';
      });
    } finally {
      setState(() {
        _isFetchingAI = false;
      });
    }
  }

  Widget _buildMyProgress() {
    if (_averagePercentage == null && _receivedAssessments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _isOffline
                ? 'No cached progress data available yet\n(Connect once to save records)'
                : 'No assessments received yet to show progress',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final percentColor = _getPercentageColor(_averagePercentage ?? 0);

    Map<String, CriteriaScore> criteriaMap = {};
    for (final assessment in _receivedAssessments) {
      for (final c in assessment.criteriaScores) {
        final key = c.name;
        if (criteriaMap.containsKey(key)) {
          final prev = criteriaMap[key]!;
          criteriaMap[key] = CriteriaScore(
            name: key,
            obtained: prev.obtained + c.obtained,
            max: prev.max + c.max,
          );
        } else {
          criteriaMap[key] = c;
        }
      }
    }
    var criteriaList = criteriaMap.values.toList();
    if (criteriaList.isEmpty && _averagePercentage != null) {
      criteriaList = [
        CriteriaScore(name: 'Overall Performance', obtained: _averagePercentage!, max: 100),
      ];
    }

    String advice = "Great job overall! Keep it up.";
    final weak = criteriaList.where((c) => c.percentage < 65).toList();
    if (weak.isNotEmpty) {
      final names = weak.map((c) => c.name).take(3).join(", ");
      final more = weak.length > 3 ? " + others" : "";
      advice = "Focus on $names$more — these are below 65%.";
    } else if ((_averagePercentage ?? 0) < 75) {
      advice = "Good effort (${(_averagePercentage ?? 0).toStringAsFixed(1)}% avg). Try to be more consistent!";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 6,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.85),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Your Overall Progress in ${widget.subject.name}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: percentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: percentColor.withOpacity(0.4), width: 1.5),
                    ),
                    child: Text(
                      '${(_averagePercentage ?? 0).toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: percentColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    advice,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_isOffline)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '(Offline mode - last saved data)',
                        style: TextStyle(color: Colors.orange[800], fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          Card(
            elevation: 6,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.85),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'AI Personalized Advice',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (_isFetchingAI)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_aiError != null)
                    Text(
                      _aiError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 15,
                      ),
                      textAlign: TextAlign.center,
                    )
                  else if (_aiFeedback != null)
                    SelectableText(
                      _aiFeedback!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  else
                    Center(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          Icons.lightbulb_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: Text(
                          'Get AI Study Tips',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _fetchAIFeedback,
                      ),
                    ),

                  if (_aiFeedback != null || _aiError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Center(
                        child: TextButton.icon(
                          icon: Icon(Icons.refresh, size: 20, color: Theme.of(context).colorScheme.primary),
                          label: Text(
                            'Regenerate Advice',
                            style: TextStyle(color: Theme.of(context).colorScheme.primary),
                          ),
                          onPressed: _fetchAIFeedback,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          Card(
            elevation: 6,
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.85),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Performance by Criteria',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 300,
                    child: criteriaList.isEmpty
                        ? const Center(
                            child: Text(
                              'No detailed criteria data yet\n(Will appear after assessments include scores)',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 15),
                            ),
                          )
                        : BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: 100,
                              minY: 0,
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 80,
                                    getTitlesWidget: (value, meta) {
                                      final i = value.toInt();
                                      if (i < 0 || i >= criteriaList.length) return const Text('');
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: RotatedBox(
                                          quarterTurns: 3,
                                          child: Text(
                                            criteriaList[i].name,
                                            style: const TextStyle(fontSize: 10),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (v, meta) => Text('${v.toInt()}%'),
                                  ),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              barGroups: criteriaList.asMap().entries.map((e) {
                                final idx = e.key;
                                final item = e.value;
                                return BarChartGroupData(
                                  x: idx,
                                  barRods: [
                                    BarChartRodData(
                                      toY: item.percentage.clamp(0.0, 100.0),
                                      color: _criteriaColors[idx % _criteriaColors.length],
                                      width: 26,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                  if (criteriaList.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Bars show average performance per criterion across all received assessments',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Chat button is now correctly on Scaffold
  floatingActionButton: FloatingActionButton.extended(
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AIChatScreen()),
      );
    },
    icon: const Icon(Icons.chat_bubble_outline),
    label: const Text('Chat with AI Tutor'),
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
  ),

  bottomNavigationBar: _isAdmin
      ? BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.send_outlined), label: 'Admin Provided'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Student Assessments'),
            BottomNavigationBarItem(icon: Icon(Icons.person_search), label: 'All Users'),
          ],
        )
      : BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'My Progress'),
            BottomNavigationBarItem(icon: Icon(Icons.send_outlined), label: 'Provided'),
            BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), label: 'Received'),
          ],
        ),
  );
}

// Your original methods (unchanged)
Widget _buildAssessmentsProvided() {
  if (_givenAssessments.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send_outlined, size: 72, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 24),
            Text('No assessments provided yet', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('When you assess peers, they will appear here.', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.send_outlined, color: Theme.of(context).colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    'You have provided ${_givenAssessments.length} assessment${_givenAssessments.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _givenAssessments.length,
          itemBuilder: (context, index) {
            return _buildAssessmentCard(_givenAssessments[index]);
          },
        ),
      ),
    ],
  );
}
Widget _buildFeedbackReceived() {
    if (_receivedAssessments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 24),
              Text('No feedback received yet', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text('Peer assessments will appear here once submitted.', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, color: Theme.of(context).colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'You have received ${_receivedAssessments.length} assessment${_receivedAssessments.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _receivedAssessments.length,
            itemBuilder: (context, index) {
              return _buildAssessmentCard(_receivedAssessments[index], isReceived: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdminProvided() {
    if (_adminProvided.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send_outlined, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 24),
              Text('No assessments provided by you yet', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text('Assessments you gave to students will appear here.', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _adminProvided.length,
      itemBuilder: (context, index) {
        return _buildAssessmentCard(_adminProvided[index], showAssessor: false);
      },
    );
  }

  Widget _buildStudentPeerAssessments() {
    if (_studentPeerAssessments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 24),
              Text('No student-to-student assessments yet', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text('Peer assessments between students will appear here.', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _studentPeerAssessments.length,
      itemBuilder: (context, index) {
        return _buildAssessmentCard(_studentPeerAssessments[index], showAssessor: true);
      },
    );
  }

  Widget _buildAllUsersTab() {
    if (_allUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search, size: 72, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 24),
              Text('No users found', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text('Registered accounts will appear here.', style: Theme.of(context).textTheme.bodyLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allUsers.length,
      itemBuilder: (context, index) {
        final user = _allUsers[index];
        final accent = _accentColors[index % _accentColors.length];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: accent.withOpacity(0.2),
              child: Text(
                user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              user.fullName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user.rollNumber.isNotEmpty)
                  Text('Roll No: ${user.rollNumber}'),
                Text('Email: ${user.email}'),
                Text(
                  user.isAdmin ? 'Role: Admin' : 'Role: User',
                  style: TextStyle(
                    color: user.isAdmin ? Colors.deepPurple : Colors.blueGrey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSomeData =
        _averagePercentage != null ||
        _givenAssessments.isNotEmpty ||
        _receivedAssessments.isNotEmpty ||
        (_isAdmin && (_adminProvided.isNotEmpty || _studentPeerAssessments.isNotEmpty || _allUsers.isNotEmpty));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject.name} - Records'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_isOffline && hasSomeData && !_isLoading)
            Container(
              width: double.infinity,
              color: Colors.orange.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                "Offline • Showing recently loaded data",
                style: TextStyle(
                  color: Colors.deepOrange,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading && !hasSomeData
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty && !hasSomeData
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isOffline ? Icons.cloud_off : Icons.error_outline,
                                size: 64,
                                color: _isOffline ? Colors.orange : Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _error,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      )
                    : IndexedStack(
                        index: _currentIndex,
                        children: _isAdmin
                            ? [
                                _buildAdminProvided(),
                                _buildStudentPeerAssessments(),
                                _buildAllUsersTab(),
                              ]
                            : [
                                _buildMyProgress(),
                                _buildAssessmentsProvided(),
                                _buildFeedbackReceived(),
                              ],
                      ),
          ),
        ],
      ),
      // Chat button added here (correct place)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AIChatScreen()),
          );
        },
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Chat with AI Tutor'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      bottomNavigationBar: _isAdmin
          ? BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.send_outlined), label: 'Admin Provided'),
                BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'Student Assessments'),
                BottomNavigationBarItem(icon: Icon(Icons.person_search), label: 'All Users'),
              ],
            )
          : BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'My Progress'),
                BottomNavigationBarItem(icon: Icon(Icons.send_outlined), label: 'Provided'),
                BottomNavigationBarItem(icon: Icon(Icons.inbox_outlined), label: 'Received'),
              ],
            ),
    );
  }

// ... (keep all your other methods _buildFeedbackReceived, _buildAdminProvided, etc. exactly as they were in your original file)