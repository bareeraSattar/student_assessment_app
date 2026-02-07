import 'package:flutter/material.dart';
import 'api_service.dart';
import 'presentation_assessment_screen.dart';
import 'presentation_records_screen.dart';

class PresentationDetailScreen extends StatelessWidget {
  final Map<String, dynamic> presentation;
  final String subjectName;
  final String userRollNumber;
  final int isAdmin;

  const PresentationDetailScreen({
    super.key,
    required this.presentation,
    required this.subjectName,
    required this.userRollNumber,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final participants = (presentation['participant_rolls'] ?? '').toString().split(',').where((e) => e.isNotEmpty).toList();
    final isCompleted = (presentation['status'] ?? 'scheduled') == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text('Presentation Details${isCompleted ? ' (Completed)' : ''}'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${presentation['presentation_date'] ?? 'TBD'}', style: Theme.of(context).textTheme.titleLarge),
            Text('Type: ${presentation['type'] ?? 'Unknown'}'),
            Text('Status: ${presentation['status'] ?? 'scheduled'}'),
            Text('Participants: ${participants.join(', ')}'),
            Text('Added by: ${presentation['assessor_name'] ?? 'Unknown'}'),
            if (presentation['notes'] != null && presentation['notes'].toString().isNotEmpty)
              Text('Notes: ${presentation['notes']}'),
            const SizedBox(height: 32),

            // Add Criteria (Teacher only) - unchanged
            if (isAdmin == 1)
              FilledButton.icon(
                icon: const Icon(Icons.add_circle),
                label: const Text('Add Criteria'),
                onPressed: () => _showAddCriteriaDialog(context, subjectId: presentation['subject_id'] ?? 0),
              ),

            const SizedBox(height: 16),

            // Assess Button - disabled if completed
            FilledButton.icon(
              icon: const Icon(Icons.rate_review),
              label: const Text('Assess Presentation'),
              style: FilledButton.styleFrom(
                backgroundColor: isCompleted ? Colors.grey : null,
                foregroundColor: isCompleted ? Colors.white70 : null,
              ),
              onPressed: isCompleted
                  ? null
                  : () {
                      final isParticipant = participants.contains(userRollNumber);
                      if (isAdmin != 1 && isParticipant) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('You cannot assess your own presentation'), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PresentationAssessmentScreen(
                            presentationId: presentation['id'],
                            subjectId: presentation['subject_id'] ?? 0,
                            presentationTitle: presentation['presentation_date'] ?? 'Presentation',
                            participantRolls: participants,
                            isTeacher: isAdmin == 1,
                          ),
                        ),
                      );
                    },
            ),

            const SizedBox(height: 16),

            // View Results - always active, but emphasize for completed
            FilledButton.icon(
              icon: const Icon(Icons.analytics),
              label: Text(isCompleted ? 'View Results' : 'View Results (if available)'),
              style: FilledButton.styleFrom(
                backgroundColor: isCompleted ? Colors.green.shade700 : null,
                foregroundColor: isCompleted ? Colors.white : null,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PresentationRecordsScreen(
                      presentationId: presentation['id'],
                      presentationTitle: presentation['presentation_date'] ?? 'Presentation',
                      subjectName: subjectName,
                      userRollNumber: userRollNumber, // pass for student highlighting/filtering
                    ),
                  ),
                );
              },
            ),
          ],
        ),
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
              if (name.isEmpty || maxMarks <= 0) return;

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