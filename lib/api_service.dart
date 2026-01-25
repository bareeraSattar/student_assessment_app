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

  static Future<List<Criteria>> getCriteria(int subjectId) async {
    final online = await _isOnline();
    final cacheKey = 'criteria_for_subject_$subjectId';

    if (online) {
      try {
        final response = await http.get(Uri.parse('$baseUrl/get_criteria.php?subject_id=$subjectId')).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] != 'success') throw Exception(data['message'] ?? 'Error');
          final List list = data['criteria'] ?? [];
          final criteriaList = list.map((e) => Criteria.fromJson(e)).toList();
          await _cacheData(_criteriaBox, cacheKey, criteriaList, (c) => c.toJson());
          return criteriaList;
        }
      } catch (e) {
        debugPrint('Criteria error: $e');
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
  }) async {
    final online = await _isOnline();

    String cacheKey = 'assessments';
    if (subjectId != null) cacheKey += '_subject_$subjectId';
    if (studentId != null) cacheKey += '_student_$studentId';
    if (latestOnly) cacheKey += '_latest';

    if (online) {
      try {
        String url = '$baseUrl/get_assessments.php?';
        if (subjectId != null) url += 'subject_id=$subjectId&';
        if (studentId != null) url += 'student_id=$studentId&';
        if (latestOnly) url += 'latest_only=1&';
        if (url.endsWith('&')) url = url.substring(0, url.length - 1);

        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
        final data = jsonDecode(response.body);
        if (data['status'] != 'success') throw Exception(data['message'] ?? 'Failed');
        final List list = data['assessments'] ?? [];
        final assessments = list.map((e) => Assessment.fromJson(e as Map<String, dynamic>)).toList();
        await _cacheData(_assessmentsBox, cacheKey, assessments, (a) => a.toJson());
        return assessments;
      } catch (e) {
        debugPrint('Assessments error: $e');
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
        String url = '$baseUrl/get_assessments.php?subject_id=$subjectId';
        if (rollNumber.isNotEmpty) url += '&user_roll_number=${Uri.encodeComponent(rollNumber)}';
        url += '&is_admin=${isAdmin ? 1 : 0}';

        debugPrint('Fetching records from: $url');

        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw Exception('Server returned ${response.statusCode}');
        }

        final rawBody = response.body;
        debugPrint('Raw API response body: $rawBody'); // ← Helps debugging

        final data = jsonDecode(rawBody) as Map<String, dynamic>;
        debugPrint('API response status: ${data['status']}');

        if (data['status'] != 'success') {
          debugPrint('API returned non-success: ${data['message']}');
          throw Exception(data['message'] ?? 'API returned error');
        }

        // Safe parsing of average_percentage (handles string or number)
        final avgRaw = data['average_percentage'];
        final avgParsed = avgRaw != null ? double.tryParse(avgRaw.toString()) : null;

        return {
          'given': (data['given'] as List<dynamic>? ?? [])
              .map((e) {
                try {
                  return Assessment.fromJson(e as Map<String, dynamic>);
                } catch (parseErr) {
                  debugPrint('Error parsing given assessment: $parseErr');
                  return null;
                }
              })
              .whereType<Assessment>()
              .toList(),
          'received': (data['received'] as List<dynamic>? ?? [])
              .map((e) {
                try {
                  return Assessment.fromJson(e as Map<String, dynamic>);
                } catch (parseErr) {
                  debugPrint('Error parsing received assessment: $parseErr');
                  return null;
                }
              })
              .whereType<Assessment>()
              .toList(),
          'all_assessments': (data['all_assessments'] as List<dynamic>? ?? [])
              .map((e) {
                try {
                  return Assessment.fromJson(e as Map<String, dynamic>);
                } catch (parseErr) {
                  debugPrint('Error parsing all_assessments: $parseErr');
                  return null;
                }
              })
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
}