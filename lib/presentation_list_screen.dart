import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'api_service.dart';
import 'models.dart';
import 'presentation_records_screen.dart';
import 'presentation_assessment_screen.dart';
import 'presentation_detail_screen.dart';

class PresentationListScreen extends StatefulWidget {
  final int subjectId;
  final String subjectName;
  final String userRollNumber;
  final int isAdmin;

  const PresentationListScreen({
    super.key,
    required this.subjectId,
    required this.subjectName,
    required this.userRollNumber,
    required this.isAdmin,
  });

  @override
  State<PresentationListScreen> createState() => _PresentationListScreenState();
}

class _PresentationListScreenState extends State<PresentationListScreen> {
  late Future<List<dynamic>> _presentationsFuture;
  List<Student> _allStudents = [];

  // Same accent colors as your other screens
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
    _presentationsFuture = _fetchPresentations();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final students = await ApiService.getStudents();
      setState(() => _allStudents = students);
    } catch (e) {
      debugPrint('Failed to load students: $e');
      setState(() => _allStudents = []);
    }
  }

  Future<List<dynamic>> _fetchPresentations() async {
    try {
      return await ApiService.getPresentationsBySubject(widget.subjectId, includeCompleted: true);
    } catch (e) {
      debugPrint('Fetch presentations error: $e');
      return [];
    }
  }

  Future<void> _schedulePresentation() async {
    DateTime? selectedDateTime;
    String selectedType = 'individual';
    List<String> selectedRolls = [];
    final notesController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule Presentation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(
                    selectedDateTime == null
                        ? 'Select Date & Time'
                        : DateFormat('dd MMM yyyy, hh:mm a').format(selectedDateTime!),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (date == null) return;

                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time == null) return;

                      setDialogState(() {
                        selectedDateTime = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: const [
                    DropdownMenuItem(value: 'individual', child: Text('Individual')),
                    DropdownMenuItem(value: 'group', child: Text('Group')),
                  ],
                  onChanged: (value) {
                    setDialogState(() {
                      selectedType = value!;
                      selectedRolls = value == 'individual' ? [widget.userRollNumber] : [];
                    });
                  },
                ),
                if (selectedType == 'group')
                  ListTile(
                    title: Text('Participants (${selectedRolls.length} selected)'),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: () async {
                        final selected = await showDialog<List<String>>(
                          context: context,
                          builder: (ctx) => MultiSelectDialog(
                            items: _allStudents.map((s) => s.rollNo).toList(),
                            initialSelected: selectedRolls,
                          ),
                        );
                        if (selected != null) setDialogState(() => selectedRolls = selected);
                      },
                    ),
                  ),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedDateTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select date & time')));
                  return;
                }
                if (selectedType == 'group' && selectedRolls.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one participant')));
                  return;
                }

                final response = await ApiService.schedulePresentation(
                  subjectId: widget.subjectId,
                  participantRolls: selectedRolls.join(','),
                  presentationDate: DateFormat('yyyy-MM-dd HH:mm:ss').format(selectedDateTime!),
                  notes: notesController.text.trim(),
                );

                Navigator.pop(context);

                if (response['success'] == true || response['message']?.contains('success') == true) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scheduled!'), backgroundColor: Colors.green));
                  setState(() {
                    _presentationsFuture = _fetchPresentations();
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(response['message'] ?? 'Failed'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Presentations - ${widget.subjectName}')),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _presentationsFuture = _fetchPresentations()),
        child: FutureBuilder<List<dynamic>>(
          future: _presentationsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
            final presentations = snapshot.data ?? [];
            if (presentations.isEmpty) return const Center(child: Text('No presentations scheduled'));

            return ListView.builder(
              itemCount: presentations.length,
              itemBuilder: (context, index) {
                final pres = presentations[index];
                final participants = (pres['participant_rolls'] ?? '').toString().split(',').where((e) => e.isNotEmpty).toList();
                final isCompleted = (pres['status'] ?? 'scheduled') == 'completed';
                final accentColor = _accentColors[index % _accentColors.length];

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accentColor.withOpacity(0.08),
                          accentColor.withOpacity(0.03),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pres['presentation_date'] ?? 'Date TBD',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: accentColor.withOpacity(0.9),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text('Type: ${pres['type'] ?? 'Unknown'} • Status: ${pres['status'] ?? 'scheduled'}'),
                          Text('Participants: ${pres['participant_names'] ?? participants.join(', ')}'),
                          Text('Added by: ${pres['assessor_name'] ?? 'Unknown'}'),
                          if (pres['notes'] != null && pres['notes'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('Notes: ${pres['notes']}', style: TextStyle(color: Colors.grey[700])),
                            ),
                          const SizedBox(height: 20),

                          // Redesigned button row - more spacious and colorful
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              // Assess Button
                              SizedBox(
                                width: 140,
                                child: OutlinedButton.icon(
                                  icon: Icon(Icons.rate_review, size: 20, color: isCompleted ? Colors.grey : accentColor),
                                  label: Text('Assess', style: TextStyle(color: isCompleted ? Colors.grey : accentColor, fontWeight: FontWeight.w600)),
                                  onPressed: isCompleted
                                      ? null
                                      : () {
                                          final isParticipant = participants.contains(widget.userRollNumber);
                                          if (widget.isAdmin != 1 && isParticipant) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('You cannot assess your own presentation'), backgroundColor: Colors.orange),
                                            );
                                            return;
                                          }

                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => PresentationAssessmentScreen(
                                                presentationId: pres['id'],
                                                subjectId: widget.subjectId,
                                                presentationTitle: pres['presentation_date'] ?? 'Presentation',
                                                participantRolls: participants,
                                                isTeacher: widget.isAdmin == 1,
                                              ),
                                            ),
                                          ).then((_) => setState(() => _presentationsFuture = _fetchPresentations()));
                                        },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: isCompleted ? Colors.grey.shade300 : accentColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                              ),

                              // Details Button
                              SizedBox(
                                width: 140,
                                child: OutlinedButton.icon(
                                  icon: Icon(Icons.info_outline, size: 20, color: accentColor),
                                  label: Text('Details', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PresentationDetailScreen(
                                          presentation: pres,
                                          subjectName: widget.subjectName,
                                          userRollNumber: widget.userRollNumber,
                                          isAdmin: widget.isAdmin,
                                        ),
                                      ),
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: accentColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                              ),

                              // Records / Results Button
                              SizedBox(
                                width: 140,
                                child: OutlinedButton.icon(
                                  icon: Icon(Icons.analytics, size: 20, color: isCompleted ? accentColor : Colors.grey),
                                  label: Text(
                                    widget.isAdmin == 1 ? 'Records' : 'Results',
                                    style: TextStyle(color: isCompleted ? accentColor : Colors.grey, fontWeight: FontWeight.w600),
                                  ),
                                  onPressed: isCompleted
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => PresentationRecordsScreen(
                                                presentationId: pres['id'],
                                                presentationTitle: pres['presentation_date'] ?? 'Presentation',
                                                subjectName: widget.subjectName,
                                                userRollNumber: widget.isAdmin == 1 ? null : widget.userRollNumber, // Admin sees all
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(color: isCompleted ? accentColor : Colors.grey.shade300),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                  ),
                                ),
                              ),

                              // Criteria Button (Admin only)
                              if (widget.isAdmin == 1)
                                SizedBox(
                                  width: 140,
                                  child: OutlinedButton.icon(
                                    icon: Icon(Icons.add_circle, size: 20, color: accentColor),
                                    label: Text('Criteria', style: TextStyle(color: accentColor, fontWeight: FontWeight.w600)),
                                    onPressed: () => _showAddCriteriaDialog(context, subjectId: widget.subjectId),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      side: BorderSide(color: accentColor),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _schedulePresentation,
        label: const Text('Schedule'),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _showAddCriteriaDialog(BuildContext context, {required int subjectId}) {
    final nameController = TextEditingController();
    final maxMarksController = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Criteria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: maxMarksController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max Marks')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final maxMarks = double.tryParse(maxMarksController.text.trim()) ?? 0;
              if (name.isEmpty || maxMarks <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill all fields')));
                return;
              }

              await ApiService.addCriteriaForPresentation(
                subjectId: subjectId,
                name: name,
                maxMarks: maxMarks,
              );

              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Criteria added')));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class MultiSelectDialog extends StatefulWidget {
  final List<String> items;
  final List<String> initialSelected;

  const MultiSelectDialog({super.key, required this.items, required this.initialSelected});

  @override
  State<MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  late List<String> selected;

  @override
  void initState() {
    super.initState();
    selected = List.from(widget.initialSelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Participants'),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView.builder(
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final roll = widget.items[index];
            return CheckboxListTile(
              title: Text(roll),
              value: selected.contains(roll),
              onChanged: (val) {
                setState(() {
                  if (val == true) selected.add(roll);
                  else selected.remove(roll);
                });
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}