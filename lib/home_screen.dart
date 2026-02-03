import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'api_service.dart';
import 'models.dart';
import 'assessment_screen.dart';
import 'records_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const HomeScreen({super.key, this.userData});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Subject> _subjects = [];
  bool _isLoading = true;
  String _error = '';
  bool _isOffline = false;

  String? _studentName;
  String? _rollNo;
  String? _email;

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
    _loadUserData();
    _checkOfflineAndLoadSubjects();
  }

  Future<void> _checkOfflineAndLoadSubjects() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() => _isOffline = connectivityResult == ConnectivityResult.none);

    await _loadSubjects();
  }

  Future<void> _loadUserData() async {
    if (widget.userData != null) {
      _updateUserFromMap(widget.userData!);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('current_user');
    if (userJson != null) {
      try {
        final userMap = jsonDecode(userJson) as Map<String, dynamic>;
        _updateUserFromMap(userMap);
      } catch (e) {
        print('Failed to parse saved user: $e');
      }
    }
  }

  void _updateUserFromMap(Map<String, dynamic> map) {
    setState(() {
      _studentName = map['full_name'] as String? ?? map['name'] as String?;
      _rollNo     = map['roll_number'] as String? ?? map['rollNo'] as String?;
      _email      = map['email'] as String?;
    });
  }

  Future<void> _loadSubjects() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });

      final subjects = await ApiService.getSubjects();
      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load subjects: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged out successfully'), backgroundColor: Colors.orangeAccent),
    );

    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // ──────────────────────────────────────────────
  // NEW: Password check before opening assessment
  // ──────────────────────────────────────────────
  Future<bool> _checkAssessmentPassword() async {
    // Admin bypass
    final isAdmin = await ApiService.isCurrentUserAdmin();
    if (isAdmin) return true;

    // Show dialog for students
    String? enteredPassword;

    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assessment Password Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please enter the password to access the assessment.'),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                hintText: 'Enter password',
              ),
              onChanged: (value) => enteredPassword = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (enteredPassword == null || enteredPassword!.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Please enter a password')),
                );
                return;
              }

              final isValid = await ApiService.verifyAssessmentPassword(enteredPassword!.trim());

              if (!mounted) return;

              if (isValid) {
                Navigator.pop(dialogContext, true);
              } else {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect password'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );

    return proceed == true;
  }

  // ──────────────────────────────────────────────
  // NEW: Admin dialog to set/change/remove password
  // ──────────────────────────────────────────────
  Future<void> _showPasswordManagementDialog() async {
  String? newPassword;
  bool remove = false;

  await showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // Give more vertical space to avoid overflow
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80.0),
      // Make dialog scrollable when keyboard appears or content is tall
      scrollable: true,
      title: const Text('Manage Assessment Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set a new password or remove the existing one.'),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
                hintText: 'Leave empty to remove/disable',
              ),
              onChanged: (value) => newPassword = value,
            ),
            const SizedBox(height: 12),
            const Text(
              '• Enter a value → set/change password\n'
              '• Leave blank → remove password requirement',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () {
            remove = true;
            Navigator.pop(dialogContext);
          },
          child: const Text('Remove Password'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Apply'),
        ),
      ],
    ),
  );

  // If dialog was dismissed without action → do nothing
  if (newPassword == null && !remove) return;

  final passwordToSend = remove ? '' : (newPassword?.trim() ?? '');

  final success = await ApiService.setAssessmentPassword(passwordToSend);

  if (!mounted) return;

  if (success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(passwordToSend.isEmpty ? 'Password removed' : 'Password updated'),
        backgroundColor: Colors.green,
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Failed to update password'),
        backgroundColor: Colors.red,
      ),
    );
  }
}

  Future<void> _navigateToAssessment(Subject subject) async {
    final canProceed = await _checkAssessmentPassword();

    if (canProceed && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssessmentScreen(subject: subject)),
      );
    }
  }

  void _navigateToRecords(Subject subject) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => RecordsScreen(subject: subject)));
  }

  IconData _getSubjectIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('botany') || lower.contains('plant')) return Icons.spa;
    if (lower.contains('network')) return Icons.device_hub;
    if (lower.contains('data structure') || lower.contains('algorithm')) return Icons.account_tree;
    if (lower.contains('database') || lower.contains('db')) return Icons.storage;
    return Icons.book;
  }

  Color _getSubjectAccent(int index) {
    return _accentColors[index % _accentColors.length];
  }

  Widget _buildSubjectCard(Subject subject, int index) {
    final accentColor = _getSubjectAccent(index);
    final icon = _getSubjectIcon(subject.name);

    return Card(
      elevation: Theme.of(context).brightness == Brightness.light ? 1.5 : 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 36, color: accentColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      subject.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (subject.description?.isNotEmpty ?? false) ...[
                const SizedBox(height: 12),
                Text(
                  subject.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.assignment_outlined, size: 20),
                      label: const Text('Assessment'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () => _navigateToAssessment(subject),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.history_outlined, size: 20),
                      label: const Text('Records'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: accentColor.withOpacity(0.7)),
                        foregroundColor: accentColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      onPressed: () => _navigateToRecords(subject),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Card(
        elevation: isDark ? 3 : 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/uni_logo.jpeg',
                  height: 48,
                  width: 48,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.school, size: 48, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _studentName != null ? 'Welcome, $_studentName!' : 'Welcome, Student!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              if (_rollNo != null)
                Text(
                  'Roll No: $_rollNo',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                ),
              if (_email != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Email: $_email',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                'Select a subject to start assessment or view records',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_isOffline)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Offline Mode - Data from last sync',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 24),
          Text('Loading subjects...', style: Theme.of(context).textTheme.titleMedium),
          if (_isOffline)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Offline Mode - Showing cached data',
                style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
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
            Text('Something went wrong', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: _loadSubjects,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school_outlined, size: 72, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 24),
            Text('No subjects available', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text('Subjects will appear here once added in the admin panel.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverAppBar(
              floating: true,
              snap: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: Text(
                'Student Assessment',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadSubjects),

                // ─── Admin-only password management button ───
                FutureBuilder<bool>(
                  future: ApiService.isCurrentUserAdmin(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox.shrink();
                    }
                    if (snapshot.hasData && snapshot.data == true) {
                      return IconButton(
                        icon: const Icon(Icons.lock_reset_rounded),
                        tooltip: 'Manage Assessment Password',
                        onPressed: _showPasswordManagementDialog,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

                IconButton(icon: const Icon(Icons.logout_rounded), onPressed: _handleLogout),
              ],
            ),
          ],
          body: Column(
            children: [
              _buildDashboardHeader(),
              Expanded(
                child: _isLoading
                    ? _buildLoading()
                    : _error.isNotEmpty
                        ? _buildError()
                        : _subjects.isEmpty
                            ? _buildEmpty()
                            : RefreshIndicator(
                                onRefresh: _loadSubjects,
                                child: ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                  itemCount: _subjects.length,
                                  itemBuilder: (context, index) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: _buildSubjectCard(_subjects[index], index),
                                  ),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}