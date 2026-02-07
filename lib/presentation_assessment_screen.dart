import 'package:flutter/material.dart';
import 'api_service.dart';
import 'models.dart';

class PresentationAssessmentScreen extends StatefulWidget {
  final int presentationId;
  final int subjectId;
  final String presentationTitle;
  final List<String> participantRolls;
  final bool isTeacher;

  const PresentationAssessmentScreen({
    super.key,
    required this.presentationId,
    required this.subjectId,
    required this.presentationTitle,
    required this.participantRolls,
    required this.isTeacher,
  });

  @override
  State<PresentationAssessmentScreen> createState() => _PresentationAssessmentScreenState();
}

class _PresentationAssessmentScreenState extends State<PresentationAssessmentScreen> {
  List<Criteria> _criteria = [];
  String? _selectedStudentRoll;
  Map<int, double> _marks = {};
  bool _isLoading = true;
  String _error = '';
  bool _isSubmitting = false;

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

  @override
  void initState() {
    super.initState();
    _loadCriteria();
    if (widget.participantRolls.length == 1) {
      _selectedStudentRoll = widget.participantRolls.first.trim();
    }
  }

  Future<void> _loadCriteria() async {
    try {
      final allCriteria = await ApiService.getCriteria(widget.subjectId);
      setState(() {
        _criteria = allCriteria.where((c) => c.isPresentation).toList();
        for (var c in _criteria) {
          _marks[c.id] = 0.0;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load presentation criteria: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submitAssessment() async {
    if (_selectedStudentRoll == null || _selectedStudentRoll!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student to assess')),
      );
      return;
    }

    if (_criteria.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No presentation criteria available')),
      );
      return;
    }

    final cleanRoll = _selectedStudentRoll!.trim();

    setState(() => _isSubmitting = true);

    final scores = _criteria.map((c) {
      return {
        'criteria_id': c.id,
        'marks_awarded': _marks[c.id] ?? 0.0,
        'comments': '', // No comments field
      };
    }).toList();

    try {
      final response = await ApiService.submitPresentationAssessment(
        presentationId: widget.presentationId,
        studentRoll: cleanRoll,
        subjectId: widget.subjectId,
        scores: scores,
      );

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Assessment submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Failed to submit'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isTeacher ? 'Assess Presentation' : 'Peer Assessment'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 18),
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Card
                        Card(
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.indigo[50]!,
                                  Colors.blue[50]!,
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.presentationTitle,
                                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo[900],
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Presentation ID: ${widget.presentationId}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Colors.grey[700],
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Student Selector
                        if (widget.participantRolls.length > 1) ...[
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Select Student to Assess',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                            value: _selectedStudentRoll,
                            items: widget.participantRolls.map((roll) {
                              final clean = roll.trim();
                              return DropdownMenuItem(value: clean, child: Text(clean));
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedStudentRoll = value?.trim();
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                        ] else if (widget.participantRolls.isNotEmpty) ...[
                          Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            color: Colors.blue[50],
                            child: ListTile(
                              leading: Icon(Icons.person, color: Colors.blue[700]),
                              title: Text(
                                'Assessing: ${widget.participantRolls.first.trim()}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Peer hint
                        if (!widget.isTeacher) ...[
                          Card(
                            elevation: 2,
                            color: Colors.indigo[50],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Your assessment is anonymous to the presenter',
                                style: TextStyle(color: Colors.indigo[800], fontWeight: FontWeight.w500),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Criteria Title
                        Text(
                          'Presentation Assessment Criteria',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),

                        if (_criteria.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(40.0),
                              child: Column(
                                children: [
                                  Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No presentation-specific criteria added yet.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[700], fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Ask your teacher to add some from the presentation details.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._criteria.asMap().entries.map((entry) {
                            final index = entry.key;
                            final c = entry.value;
                            final accent = _accentColors[index % _accentColors.length];

                            return Card(
                              margin: const EdgeInsets.only(bottom: 20),
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withOpacity(0.08),
                                      accent.withOpacity(0.03),
                                    ],
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              c.name,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: accent.withOpacity(0.9),
                                                  ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: accent.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${_marks[c.id]?.toStringAsFixed(1) ?? '0.0'} / ${c.maxMarks}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: accent,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 6,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
                                        ),
                                        child: Slider(
                                          value: _marks[c.id] ?? 0.0,
                                          min: 0.0,
                                          max: c.maxMarks.toDouble(),
                                          divisions: c.maxMarks.toInt(),
                                          label: (_marks[c.id] ?? 0.0).toStringAsFixed(1),
                                          activeColor: accent,
                                          inactiveColor: accent.withOpacity(0.3),
                                          onChanged: (value) {
                                            setState(() => _marks[c.id] = value);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),

                        const SizedBox(height: 48),

                        Center(
                          child: SizedBox(
                            width: double.infinity,
                            height: 60,
                            child: FilledButton.icon(
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  : const Icon(Icons.send, size: 28),
                              label: Text(
                                _isSubmitting ? 'Submitting...' : 'Submit Assessment',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _accentColors[widget.presentationId % _accentColors.length],
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                elevation: 6,
                                shadowColor: _accentColors[widget.presentationId % _accentColors.length].withOpacity(0.4),
                              ),
                              onPressed: _isSubmitting ? null : _submitAssessment,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }
}