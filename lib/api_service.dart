import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class ApiService {
  static const String baseUrl = 'https://bareerasattar.site/e_api';

  // Hive box names
  static const String _subjectsBox    = 'subjects_cache';
  static const String _studentsBox    = 'students_cache';
  static const String _criteriaBox    = 'criteria_cache';
  static const String _assessmentsBox = 'assessments_cache';

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  static Future<bool> _isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _cacheData<T>(
    String boxName,
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    try {
      final box = await Hive.openBox(boxName);
      final jsonList = items.map(toJson).toList();
      await box.put(key, jsonEncode(jsonList));
    } catch (e) {
      if (kDebugMode) debugPrint('Cache write failed ($boxName): $e');
    }
  }

  static Future<List<T>?> _getCachedData<T>(
    String boxName,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final box = await Hive.openBox(boxName);
      final jsonString = box.get(key);
      if (jsonString == null) return null;
      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((e) => fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('Cache read failed ($boxName): $e');
      return null;
    }
  }

  static Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  static Future<bool> isCurrentUserAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
  }

  static Future<String> getCurrentUserRoll() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('roll_number') ?? '';
  }

  // ──────────────────────────────────────────────
  // GET Subjects
  // ──────────────────────────────────────────────

  static Future<List<Subject>> getSubjects() async {
    final online = await _isOnline();

    if (online) {
      try {
        final response = await http.get(Uri.parse('$baseUrl/get_subjects.php')).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List list = data['subjects'] ?? data ?? [];
          final subjects = list.map((json) => Subject.fromJson(json)).toList();
          await _cacheData(_subjectsBox, 'all_subjects', subjects, (s) => s.toJson());
          return subjects;
        }
      } catch (e) {
        debugPrint('Subjects error: $e');
      }
    }

    final cached = await _getCachedData(_subjectsBox, 'all_subjects', Subject.fromJson);
    if (cached != null && cached.isNotEmpty) return cached;
    throw Exception('No subjects available');
  }

  // ──────────────────────────────────────────────
  // GET Students
  // ──────────────────────────────────────────────

  static Future<List<Student>> getStudents() async {
    final online = await _isOnline();

    if (online) {
      try {
        final response = await http.get(Uri.parse('$baseUrl/get_students.php')).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List list = data['students'] ?? data['data'] ?? data ?? [];
          final students = list.map((json) => Student.fromJson(json)).toList();
          await _cacheData(_studentsBox, 'all_students', students, (s) => s.toJson());
          return students;
        }
      } catch (e) {
        debugPrint('Students error: $e');
      }
    }

    final cached = await _getCachedData(_studentsBox, 'all_students', Student.fromJson);
    if (cached != null && cached.isNotEmpty) return cached;
    throw Exception('No students available');
  }

  static Future<List<Student>> fetchStudentsForSignup() async {
    return getStudents();
  }

  // ──────────────────────────────────────────────
  // GET Criteria
  // ──────────────────────────────────────────────

  static Future<List<Criteria>> getCriteria(
  int subjectId, {
  String type = 'assessment',  // default to 'assessment' so most calls are safe
}) async {
  final online = await _isOnline();
  final cacheKey = 'criteria_for_subject_${subjectId}_type_$type';

  if (online) {
    try {
      String url = '$baseUrl/get_criteria.php?subject_id=$subjectId';
      if (type == 'assessment' || type == 'presentation') {
        url += '&type=$type';
      }

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] != 'success') throw Exception(data['message'] ?? 'Error');
        final List list = data['criteria'] ?? [];
        final criteriaList = list.map((e) => Criteria.fromJson(e)).toList();
        await _cacheData(_criteriaBox, cacheKey, criteriaList, (c) => c.toJson());
        return criteriaList;
      }
    } catch (e) {
      debugPrint('Criteria error (type=$type): $e');
    }
  }

  final cached = await _getCachedData(_criteriaBox, cacheKey, Criteria.fromJson);
  if (cached != null && cached.isNotEmpty) return cached;
  throw Exception('No criteria available');
}

  // ──────────────────────────────────────────────
  // GET Assessments (original – used in other screens)
  // ──────────────────────────────────────────────

  static Future<List<Assessment>> getAssessments({
  int? subjectId,
  int? studentId,
  bool latestOnly = false,
  String type = 'assessment',  // default to regular assessments
}) async {
  final online = await _isOnline();

  String cacheKey = 'assessments_type_$type';
  if (subjectId != null) cacheKey += '_subject_$subjectId';
  if (studentId != null) cacheKey += '_student_$studentId';
  if (latestOnly) cacheKey += '_latest';

  if (online) {
    try {
      String url = '$baseUrl/get_assessments.php?';
      if (subjectId != null) url += 'subject_id=$subjectId&';
      if (studentId != null) url += 'student_id=$studentId&';
      if (latestOnly) url += 'latest_only=1&';
      url += 'type=$type&';

      if (url.endsWith('&')) url = url.substring(0, url.length - 1);

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body);
      if (data['status'] != 'success') throw Exception(data['message'] ?? 'Failed');

      // Try to find the list — your backend returns different keys depending on mode
      final List list = data['assessments'] 
                     ?? data['given'] 
                     ?? data['received'] 
                     ?? data['all_assessments'] 
                     ?? [];

      final assessments = list.map((e) => Assessment.fromJson(e as Map<String, dynamic>)).toList();
      await _cacheData(_assessmentsBox, cacheKey, assessments, (a) => a.toJson());
      return assessments;
    } catch (e) {
      debugPrint('Assessments error (type=$type): $e');
      final cached = await _getCachedData(_assessmentsBox, cacheKey, Assessment.fromJson);
      if (cached != null && cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  final cached = await _getCachedData(_assessmentsBox, cacheKey, Assessment.fromJson);
  if (cached != null && cached.isNotEmpty) return cached;
  throw Exception('No internet and no cached assessments available');
}

  // ──────────────────────────────────────────────
  // GET Assessments for Records Screen – UPDATED & SAFE VERSION
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAssessmentsForRecords(int subjectId) async {
  final online = await _isOnline();

  final rollNumber = await getCurrentUserRoll();
  final isAdmin = await isCurrentUserAdmin();

  if (online) {
    try {
      // Important change here ↓
      String url = '$baseUrl/get_assessments.php?subject_id=$subjectId&type=assessment';
      if (rollNumber.isNotEmpty) url += '&user_roll_number=${Uri.encodeComponent(rollNumber)}';
      url += '&is_admin=${isAdmin ? 1 : 0}';

      debugPrint('Fetching records from: $url');

      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final rawBody = response.body;
      debugPrint('Raw API response body: $rawBody');

      final data = jsonDecode(rawBody) as Map<String, dynamic>;
      debugPrint('API response status: ${data['status']}');

      if (data['status'] != 'success') {
        debugPrint('API returned non-success: ${data['message']}');
        throw Exception(data['message'] ?? 'API returned error');
      }

      final avgRaw = data['average_percentage'];
      final avgParsed = avgRaw != null ? double.tryParse(avgRaw.toString()) : null;

      return {
        'given': (data['given'] as List<dynamic>? ?? [])
            .map((e) => Assessment.fromJson(e as Map<String, dynamic>))
            .whereType<Assessment>()
            .toList(),
        'received': (data['received'] as List<dynamic>? ?? [])
            .map((e) => Assessment.fromJson(e as Map<String, dynamic>))
            .whereType<Assessment>()
            .toList(),
        'all_assessments': (data['all_assessments'] as List<dynamic>? ?? [])
            .map((e) => Assessment.fromJson(e as Map<String, dynamic>))
            .whereType<Assessment>()
            .toList(),
        'average_percentage': avgParsed,
      };
    } catch (e) {
      debugPrint('Records fetch error: $e');
      return {
        'given': <Assessment>[],
        'received': <Assessment>[],
        'all_assessments': <Assessment>[],
        'average_percentage': null,
      };
    }
  }

  debugPrint('Offline mode: returning empty records');
  return {
    'given': <Assessment>[],
    'received': <Assessment>[],
    'all_assessments': <Assessment>[],
    'average_percentage': null,
  };
}

  // ──────────────────────────────────────────────
  // POST: Login
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identifier': identifier.trim(),
        'password': password.trim(),
      }),
    );

    final result = jsonDecode(response.body);
    if (result['success'] != true) {
      throw Exception(result['message'] ?? 'Login failed');
    }

    final prefs = await SharedPreferences.getInstance();
    final user = result['user'] as Map<String, dynamic>;

    await prefs.setInt('user_id', user['id']);
    await prefs.setString('roll_number', user['roll_number'] ?? '');
    await prefs.setString('full_name', user['full_name'] ?? '');
    await prefs.setBool('is_admin', user['is_admin'] == 1);
    await prefs.setString('current_user', jsonEncode(user));

    if (kDebugMode) {
      debugPrint('User saved: roll=${user['roll_number']}, is_admin=${user['is_admin']}');
    }

    return result;
  }

  // ──────────────────────────────────────────────
  // POST: Signup
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> signup({
    required String rollNo,
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/signup.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'roll_number': rollNo.trim(),
        'email': email.trim(),
        'password': password.trim(),
      }),
    );

    final result = jsonDecode(response.body);
    if (result['success'] != true) throw Exception(result['message'] ?? 'Signup failed');
    return result;
  }

  // ──────────────────────────────────────────────
  // POST: Submit Assessment
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> submitAssessment({
    required int studentId,
    required int subjectId,
    required String assessmentDate,
    required List<Map<String, dynamic>> criteriaScores,
    String? feedbackText,
  }) async {
    final assessorId = await getCurrentUserId();
    if (assessorId == null) {
      throw Exception('No logged-in user found. Please login again.');
    }

    final body = {
      'assessor_id': assessorId,
      'student_id': studentId,
      'subject_id': subjectId,
      'assessment_date': assessmentDate.trim(),
      'criteria_scores': criteriaScores,
      if (feedbackText != null && feedbackText.isNotEmpty) 'feedback_text': feedbackText.trim(),
    };

    if (kDebugMode) {
      debugPrint('Submitting assessment payload: ${jsonEncode(body)}');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/submit_assessment.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final result = jsonDecode(response.body);
    if (result['status'] != 'success') {
      throw Exception(result['message'] ?? 'Submission failed');
    }

    return result;
  }

  static Future<Map<String, dynamic>> submitFeedback({
    required String feedback,
    int? assessmentId,
  }) async {
    final userId = await getCurrentUserId();
    if (userId == null) throw Exception('No logged-in user found');

    final response = await http.post(
      Uri.parse('$baseUrl/submit_feedback.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'assessment_id': assessmentId,
        'feedback_text': feedback.trim(),
        'feedback_by': 'Teacher',
      }),
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> updateAssessment({
    required int subjectId,
    required Map<String, dynamic> assessmentData,
  }) async {
    final userId = await getCurrentUserId();
    if (userId == null) throw Exception('No user');

    final response = await http.post(
      Uri.parse('$baseUrl/update_assessment.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'student_id': userId,
        'subject_id': subjectId,
        ...assessmentData,
      }),
    );

    return jsonDecode(response.body);
  }

  // ──────────────────────────────────────────────
  // POST: Get AI Feedback (new - added for progress/records screen)
  // ──────────────────────────────────────────────

  static Future<Map<String, dynamic>> getAIFeedback({
    required int subjectId,
    String? subjectName,              // optional - helps make feedback better
    String? customSummary,            // optional - if you want to send pre-built summary
  }) async {
    final online = await _isOnline();
    if (!online) {
      return {
        'success': false,
        'message': 'No internet connection',
      };
    }

    final rollNumber = await getCurrentUserRoll();
    if (rollNumber.isEmpty) {
      return {
        'success': false,
        'message': 'User roll number not found. Please login again.',
      };
    }

    final url = Uri.parse('$baseUrl/get_ai_feedback.php');

    final body = {
      'user_roll_number': rollNumber,
      'subject_id': subjectId,
      if (subjectName != null && subjectName.isNotEmpty) 'subject_name': subjectName,
      if (customSummary != null && customSummary.isNotEmpty) 'performance_summary': customSummary,
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return {
          'success': false,
          'message': 'Server error ${response.statusCode}',
        };
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['status'] == 'success') {
        return {
          'success': true,
          'feedback': data['feedback'] as String? ?? '',
          'summary_used': data['summary'] as String? ?? '',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] as String? ?? 'Failed to get AI feedback',
        };
      }
    } catch (e) {
      debugPrint('AI feedback error: $e');
      return {
        'success': false,
        'message': 'Could not connect to AI service',
      };
    }
  }

  static Future<Map<String, dynamic>> chatWithAI({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final online = await _isOnline();
    if (!online) {
      return {'reply': 'No internet connection'};
    }

    final url = Uri.parse('$baseUrl/chat_with_ai.php');

    final body = {
      'message': message,
      'history': history,
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          return {
            'success': true,
            'reply': data['reply'] as String,
          };
        } else {
          return {
            'success': false,
            'reply': data['message'] as String? ?? 'Chat failed',
          };
        }
      } else {
        return {
          'success': false,
          'reply': 'Server error ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('Chat AI error: $e');
      return {
        'success': false,
        'reply': 'Could not connect to AI',
      };
    }
  }

  // ──────────────────────────────────────────────
  // NEW: Set Assessment Password (Admin only)
  // ──────────────────────────────────────────────

  static Future<bool> setAssessmentPassword(String password) async {
    final userId = await getCurrentUserId();
    if (userId == null) {
      debugPrint('setAssessmentPassword: No user ID found');
      return false;
    }

    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      debugPrint('setAssessmentPassword: User is not admin');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/set_password.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'password': password.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['message'] == 'Password set successfully';
        if (success) {
          debugPrint('Password set successfully');
        } else {
          debugPrint('Set password failed: ${data['message']}');
        }
        return success;
      } else {
        debugPrint('Set password HTTP error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('setAssessmentPassword error: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // NEW: Verify Assessment Password
  // ──────────────────────────────────────────────

  static Future<bool> verifyAssessmentPassword(String password) async {
    if (password.trim().isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify_password.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'password': password.trim(),
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isValid = data['valid'] == true;
        debugPrint('Password verification result: $isValid');
        return isValid;
      } else {
        debugPrint('Verify password HTTP error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('verifyAssessmentPassword error: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────
  // ──────────────────────────────────────────────
  // ──────────────────────────────────────────────
  // NEW PRESENTATION METHODS – ADDED HERE SAFELY
  // ──────────────────────────────────────────────
  // ──────────────────────────────────────────────
  // ──────────────────────────────────────────────

  /// Fetch upcoming presentations for a specific subject
  /// Uses get_presentations_by_subject.php
  static Future<List<dynamic>> getPresentationsBySubject(
  int subjectId, {
  bool includeCompleted = false,
}) async {
  final online = await _isOnline();
  if (!online) {
    debugPrint('Offline - no presentations loaded');
    return [];
  }

  try {
    String url = '$baseUrl/get_presentations_by_subject.php?subject_id=$subjectId';
    if (includeCompleted) {
      url += '&include_completed=1';
    }

    final uri = Uri.parse(url);

    debugPrint('Fetching presentations: $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) {
        debugPrint('Presentations loaded: ${data.length} items');
        return data;
      } else if (data is Map && data['message'] != null) {
        debugPrint('API message: ${data['message']}');
        return [];
      } else {
        debugPrint('Unexpected response format');
        return [];
      }
    } else {
      debugPrint('Presentations HTTP error: ${response.statusCode} - ${response.body}');
      return [];
    }
  } catch (e) {
    debugPrint('getPresentationsBySubject error: $e');
    return [];
  }
}
  /// Schedule a new presentation
  /// Uses schedule_presentation.php
  static Future<Map<String, dynamic>> schedulePresentation({
    required int subjectId,
    required String participantRolls, // e.g. "CS-001,CS-005"
    required String presentationDate, // ISO: "2026-02-20T10:00:00"
    String? notes,
  }) async {
    final rollNumber = await getCurrentUserRoll();
    if (rollNumber.isEmpty) {
      return {'success': false, 'message': 'No user roll number found'};
    }

    final body = {
      'subject_id': subjectId,
      'participant_rolls': participantRolls.trim(),
      'assessor_roll_number': rollNumber,
      'presentation_date': presentationDate,
      if (notes != null && notes.isNotEmpty) 'notes': notes.trim(),
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/schedule_presentation.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 12));

      final result = jsonDecode(response.body);
      if (response.statusCode == 200 && result['message']?.toString().toLowerCase().contains('success') == true) {
        return {'success': true, 'message': result['message'] ?? 'Scheduled successfully'};
      } else {
        return {'success': false, 'message': result['message'] ?? 'Failed to schedule presentation'};
      }
    } catch (e) {
      debugPrint('schedulePresentation error: $e');
      return {'success': false, 'message': 'Network or server error'};
    }
  }

  /// Get detailed results for a specific presentation
  /// Uses get_presentation_results.php
  static Future<Map<String, dynamic>> getPresentationResults(
  int presentationId, {
  String? userRollNumber,           // null = admin/full history
  int isAdmin = 0,                  // 0 = student, 1 = admin
}) async {
  // Determine final roll and admin flag
  String? finalRoll = userRollNumber;

  // If no explicit roll passed, fallback to current user (for student mode)
  if (finalRoll == null) {
    finalRoll = await getCurrentUserRoll();
  }

  // If still no roll and not admin mode, error
  final effectiveIsAdmin = (userRollNumber == null) ? 1 : isAdmin;
  if (finalRoll == null || finalRoll.isEmpty) {
    if (effectiveIsAdmin == 1) {
      finalRoll = ''; // empty = skip roll check for admin
    } else {
      return {'success': false, 'message': 'User roll number not found'};
    }
  }

  final online = await _isOnline();
  if (!online) {
    return {'success': false, 'message': 'No internet connection'};
  }

  try {
    String url = '$baseUrl/get_presentation_results.php?presentation_id=$presentationId';

    // Only send roll if we have one (student mode)
    if (finalRoll.isNotEmpty) {
      url += '&user_roll_number=${Uri.encodeComponent(finalRoll)}';
    }

    // Always send is_admin flag
    url += '&is_admin=$effectiveIsAdmin';

    final uri = Uri.parse(url);

    debugPrint('Fetching presentation results: $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 'success') {
        return data;
      } else {
        return {'success': false, 'message': data['message'] ?? 'Failed to load results'};
      }
    } else {
      return {'success': false, 'message': 'Server error ${response.statusCode}'};
    }
  } catch (e) {
    debugPrint('getPresentationResults error: $e');
    return {'success': false, 'message': e.toString()};
  }
}
  /// Submit assessment specifically for a presentation (per student)
  /// Uses submit_presentation_assessment.php
  static Future<Map<String, dynamic>> submitPresentationAssessment({
  required int presentationId,
  required String studentRoll,
  required int subjectId,
  required List<Map<String, dynamic>> scores,
}) async {
  final rollNumber = (await getCurrentUserRoll()).trim();
  final userId = await getCurrentUserId();
  final isAdmin = await isCurrentUserAdmin();

  // Debug prints (very useful)
  print('DEBUG submitPresentationAssessment:');
  print('  - userId: $userId');
  print('  - rollNumber: "$rollNumber" (length: ${rollNumber.length})');
  print('  - isAdmin: $isAdmin');
  print('  - studentRoll (cleaned): "${studentRoll.trim()}"');

  if (userId == null) {
    return {
      'success': false,
      'message': 'User not logged in (no user ID found). Please log in again.',
    };
  }

  final body = {
    'presentation_id': presentationId,
    'assessor_roll_number': rollNumber,       // empty OK for admin
    'assessor_user_id': userId,               // primary for admin identification
    'is_admin': isAdmin ? 1 : 0,              // tells backend it's admin
    'student_roll': studentRoll.trim(),
    'subject_id': subjectId,
    'scores': scores,
  };

  try {
    final response = await http.post(
      Uri.parse('$baseUrl/submit_presentation_assessment.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 15));

    print('DEBUG - HTTP status: ${response.statusCode}');
    print('DEBUG - Raw response body: ${response.body}');

    Map<String, dynamic> result;
    try {
      result = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (jsonErr) {
      print('DEBUG - JSON parse error: $jsonErr');
      return {
        'success': false,
        'message': 'Invalid response from server',
      };
    }

    if (response.statusCode == 200 && result['success'] == true) {
      return {
        'success': true,
        'message': result['message'] ?? 'Assessment submitted successfully',
        'assessment_id': result['assessment_id'],
      };
    } else {
      return {
        'success': false,
        'message': result['message'] ?? 'Failed to submit assessment (server error)',
      };
    }
  } catch (e) {
    print('DEBUG - Submit exception: $e');
    return {
      'success': false,
      'message': 'Network or timeout error: $e',
    };
  }
}
  static Future<Map<String, dynamic>> addCriteriaForPresentation({
  required int subjectId,
  required String name,
  required double maxMarks,
  String? description,
}) async {
  final userId = await getCurrentUserId();  // must return int? (null if not logged in)
  final rollNumber = await getCurrentUserRoll(); // returns String (can be empty for admins)
  final isAdmin = await isCurrentUserAdmin(); // returns bool

  print('DEBUG - Adding criteria as: userId=$userId, roll="$rollNumber", isAdmin=$isAdmin');

  if (userId == null) {
    return {'success': false, 'message': 'User not logged in'};
  }

  final body = {
    'subject_id': subjectId,
    'name': name.trim(),
    'max_marks': maxMarks,
    if (description != null && description.isNotEmpty) 'description': description.trim(),
    'assessor_roll_number': rollNumber,
    'assessor_user_id': userId,
    'is_admin': isAdmin ? 1 : 0,
    'is_presentation': 1,
  };

  print('DEBUG - Sending body: ${jsonEncode(body)}');

  try {
    final response = await http.post(
      Uri.parse('$baseUrl/add_criteria_for_presentation.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    print('DEBUG - Server status: ${response.statusCode}, body: ${response.body}');

    final result = jsonDecode(response.body);

    if (response.statusCode == 200 && result['success'] == true) {
      return {
        'success': true,
        'message': result['message'] ?? 'Criteria added',
        'id': result['id']
      };
    } else {
      return {
        'success': false,
        'message': result['message'] ?? 'Failed to add criteria (server error)',
      };
    }
  } catch (e) {
    print('DEBUG - HTTP error: $e');
    return {'success': false, 'message': 'Network error: $e'};
  }
}
  // ──────────────────────────────────────────────
  // POST: Save FCM Token
  // ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> saveToken({
    required int userId,
    required String token,
  }) async {
    final url = Uri.parse('$baseUrl/save_token.php');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'token': token.trim(),
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        if (data['success'] == true || data['status'] == 'success') {
          debugPrint('FCM token saved on server for user $userId');
          return {'success': true, 'message': data['message'] ?? 'Token saved'};
        } else {
          debugPrint('Server rejected token save: ${data['message']}');
          return {'success': false, 'message': data['message'] ?? 'Server error'};
        }
      } else {
        debugPrint('saveToken HTTP error: ${response.statusCode} - ${response.body}');
        return {'success': false, 'message': 'Server returned ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('saveToken exception: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
    /// Load previous assessment for a specific student + subject + current user
  /// Returns the existing assessment or null
    /// Load previous assessment for a specific student + subject + current user
  /// Returns the existing assessment or null if none found
  static Future<Assessment?> getPreviousAssessmentForStudent({
    required int subjectId,
    required int studentId,
  }) async {
    final online = await _isOnline();
    final rollNumber = await getCurrentUserRoll();

    if (rollNumber.isEmpty) {
      debugPrint('Cannot load previous assessment: no roll number found');
      return null;
    }

    if (!online) {
      debugPrint('Offline mode: skipping previous assessment load');
      return null;
    }

    try {
      final url = Uri.parse(
        '$baseUrl/get_assessments.php?'
        'subject_id=$subjectId&'
        'student_id=$studentId&'
        'user_roll_number=${Uri.encodeComponent(rollNumber)}&'
        'type=assessment'
      );

      debugPrint('Fetching previous assessment: $url');

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      debugPrint('Previous assessment response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('Bad response: ${response.body.substring(0, 200)}...');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (data['status'] != 'success') {
        debugPrint('API error: ${data['message'] ?? 'Unknown error'}');
        return null;
      }

      if (data['has_existing'] != true || data['assessment'] == null) {
        debugPrint('No existing assessment found for this student/subject/assessor');
        return null;
      }

      final assessmentJson = data['assessment'] as Map<String, dynamic>;
      final assessment = Assessment.fromJson(assessmentJson);

      debugPrint('Successfully loaded previous assessment ID: ${assessment.id} '
          'with ${assessment.criteriaScores.length} criteria scores');

      return assessment;
    } catch (e, stack) {
      debugPrint('Error loading previous assessment: $e');
      debugPrint('Stack trace: $stack');
      return null;
    }
  }
}