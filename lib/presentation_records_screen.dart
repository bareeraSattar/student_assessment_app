import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api_service.dart';
import 'models.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PresentationRecordsScreen extends StatefulWidget {
  final int presentationId;
  final String presentationTitle;
  final String subjectName;
  final String? userRollNumber; // null = admin/full history, non-null = student filtered view

  const PresentationRecordsScreen({
    super.key,
    required this.presentationId,
    required this.presentationTitle,
    required this.subjectName,
    this.userRollNumber,
  });

  @override
  State<PresentationRecordsScreen> createState() => _PresentationRecordsScreenState();
}

class _PresentationRecordsScreenState extends State<PresentationRecordsScreen> {
  Map<String, dynamic>? _presentationData;
  List<dynamic> _resultsPerStudent = [];
  bool _isLoading = true;
  String _error = '';
  bool _isOffline = false;

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
    _loadPresentationResults();
  }

  Future<void> _loadPresentationResults() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      _isOffline = connectivityResult == ConnectivityResult.none;

      final result = await ApiService.getPresentationResults(
        widget.presentationId,
        userRollNumber: widget.userRollNumber,
        isAdmin: widget.userRollNumber == null ? 1 : 0,
      );

      if (result['status'] == 'success') {
        setState(() {
          _presentationData = result['presentation'] as Map<String, dynamic>?;
          _resultsPerStudent = result['results_per_student'] as List<dynamic>? ?? [];
        });
      } else {
        setState(() {
          _error = result['message'] ?? 'Failed to load records';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Color _getPercentageColor(double percentage) {
    if (percentage >= 80) return Colors.green.shade700;
    if (percentage >= 60) return Colors.blue.shade700;
    if (percentage >= 40) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Widget _buildCriteriaBarChart(List<dynamic> criteriaScores) {
    if (criteriaScores.isEmpty) return const SizedBox.shrink();

    final barGroups = criteriaScores.asMap().entries.map((entry) {
      final index = entry.key;
      final score = entry.value;

      final value = double.tryParse(score['score']?.toString() ?? '0') ?? 0.0;
      final max = double.tryParse(score['max_marks']?.toString() ?? '10') ?? 10.0;
      final color = _accentColors[index % _accentColors.length];

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            color: color,
            width: 24,
            borderRadius: BorderRadius.circular(6),
            backDrawRodData: BackgroundBarChartRodData(
              toY: max,
              color: color.withOpacity(0.15),
            ),
          ),
        ],
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            barGroups: barGroups,
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (double value, TitleMeta meta) {
                    final idx = value.toInt();
                    if (idx >= 0 && idx < criteriaScores.length) {
                      final name = criteriaScores[idx]['criteria_name']?.toString() ?? 'Crit ${idx + 1}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            name.length > 15 ? '${name.substring(0, 12)}...' : name,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      );
                    }
                    return const Text('');
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text('${value.toInt()}'),
                ),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentResultCard(dynamic studentResult) {
    final avg = double.tryParse(studentResult['average_percentage']?.toString() ?? '0') ?? 0.0;
    final count = int.tryParse(studentResult['assessment_count']?.toString() ?? '0') ?? 0;
    final assessments = studentResult['assessments'] as List<dynamic>? ?? [];

    final isCurrentUser = widget.userRollNumber != null &&
        studentResult['roll_no']?.toString().toUpperCase() == widget.userRollNumber!.toUpperCase();

    final studentIndex = int.tryParse(studentResult['student_id']?.toString() ?? '0') ?? studentResult['roll_no'].hashCode;
    final accent = _accentColors[studentIndex % _accentColors.length];

    return Card(
      elevation: isCurrentUser ? 8 : 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: isCurrentUser ? accent.withOpacity(0.05) : null,
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: accent.withOpacity(0.15),
          child: Text(
            (studentResult['name']?.toString() ?? '?')[0].toUpperCase(),
            style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          studentResult['name']?.toString() ?? 'Unknown',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent.withOpacity(0.9),
              ),
        ),
        subtitle: Text(
          'Roll: ${studentResult['roll_no'] ?? 'N/A'} • $count assessment${count == 1 ? '' : 's'}' +
              (isCurrentUser ? ' (You)' : ''),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
        ),
        childrenPadding: const EdgeInsets.all(20),
        children: [
          // Average Score
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accent.withOpacity(0.4), width: 2),
              boxShadow: [BoxShadow(color: accent.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Text(
                  '${avg.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 56, fontWeight: FontWeight.bold, color: accent),
                ),
                const SizedBox(height: 12),
                Text(
                  'Average Score',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700], fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Criteria chart (latest)
          if (assessments.isNotEmpty && assessments.first['criteria_scores'] != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    'Criteria Breakdown (Latest Assessment)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: accent, fontWeight: FontWeight.w600),
                  ),
                ),
                _buildCriteriaBarChart(assessments.first['criteria_scores']),
              ],
            ),

          const SizedBox(height: 32),

          // Assessment History - clear "who assessed whom"
          if (assessments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No assessments yet', style: TextStyle(color: Colors.grey)),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    'Assessment History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: accent),
                  ),
                ),
                ...assessments.map((ass) {
                  final assPercent = double.tryParse(ass['percentage']?.toString() ?? '0') ?? 0.0;
                  final totalMarks = double.tryParse(ass['total_marks']?.toString() ?? '0') ?? 0.0;
                  final maxMarks = double.tryParse(ass['max_possible_marks']?.toString() ?? '0') ?? 0.0;
                  final isTeacher = ass['assessor_type'] == 'teacher';
                  final assessorName = ass['assessor_name']?.toString() ?? 'Unknown Assessor';
                  final assessedName = studentResult['name']?.toString() ?? 'Unknown Student';
                  final assAccent = _accentColors[(ass['id'] as int? ?? 0) % _accentColors.length];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: ListTile(
                      leading: Icon(
                        isTeacher ? Icons.school : Icons.people,
                        color: isTeacher ? accent : accent.withOpacity(0.8),
                        size: 32,
                      ),
                      title: Text(
                        '$assessorName assessed $assessedName',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: accent.withOpacity(0.9),
                            ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${assPercent.toStringAsFixed(1)}% • $totalMarks / $maxMarks',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (ass['assessment_date'] != null)
                            Text('Assessed on: ${ass['assessment_date']}'),
                        ],
                      ),
                      trailing: Chip(
                        label: Text('${assPercent.toStringAsFixed(0)}%'),
                        backgroundColor: assAccent.withOpacity(0.15),
                        labelStyle: TextStyle(color: assAccent, fontWeight: FontWeight.bold),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userRollNumber == null ? 'Assessment Records' : 'Results'} - ${widget.presentationTitle}'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              color: Colors.orange.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: const Text(
                "Offline • Showing last loaded data if available",
                style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 80, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 24),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                onPressed: _loadPresentationResults,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _resultsPerStudent.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No assessments yet',
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Detailed assessment records will appear here once submitted.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadPresentationResults,
                            child: ListView.builder(
                              padding: const EdgeInsets.only(top: 8, bottom: 24),
                              itemCount: _resultsPerStudent.length,
                              itemBuilder: (context, index) {
                                // Student mode: filter to own result
                                // Admin mode: show all (no filter)
                                if (widget.userRollNumber != null) {
                                  if (_resultsPerStudent[index]['roll_no']?.toString().toUpperCase() !=
                                      widget.userRollNumber!.toUpperCase()) {
                                    return const SizedBox.shrink();
                                  }
                                }
                                return _buildStudentResultCard(_resultsPerStudent[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}