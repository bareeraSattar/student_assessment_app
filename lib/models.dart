// lib/models.dart

import 'package:flutter/foundation.dart'; // for debugPrint

class Student {
  final int id;
  final String name;
  final String rollNo;
  final String? className;
  final DateTime? createdAt;

  Student({
    required this.id,
    required this.name,
    required this.rollNo,
    this.className,
    this.createdAt,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: int.tryParse(json['id']?.toString() ?? json['student_id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? json['full_name']?.toString() ?? 'Unknown Student',
      rollNo: json['roll_no']?.toString() ?? json['roll_number']?.toString() ?? '',
      className: json['class_name']?.toString() ?? json['class']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roll_no': rollNo,
      'class_name': className,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class User {
  final int id;
  final String rollNumber;
  final String fullName;
  final String email;
  final bool isAdmin;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.rollNumber,
    required this.fullName,
    required this.email,
    required this.isAdmin,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      rollNumber: json['roll_number']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? json['name']?.toString() ?? 'Unknown',
      email: json['email']?.toString() ?? '',
      isAdmin: json['is_admin'] == 1 ||
          json['is_admin'] == true ||
          json['is_admin'] == '1' ||
          json['is_admin'] == 'true',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roll_number': rollNumber,
      'full_name': fullName,
      'email': email,
      'is_admin': isAdmin ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class Subject {
  final int id;
  final String name;
  final String? description;

  Subject({
    required this.id,
    required this.name,
    this.description,
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Unknown Subject',
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
    };
  }
}

class Criteria {
  final int id;
  final int subjectId;
  final String name;
  final double maxMarks;
  final double? weightage;
  final bool isPresentation;

  Criteria({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.maxMarks,
    this.weightage,
    required this.isPresentation,
  });

  factory Criteria.fromJson(Map<String, dynamic> json) {
    return Criteria(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      subjectId: int.tryParse(json['subject_id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? 'Unnamed Criteria',
      maxMarks: double.tryParse(json['max_marks']?.toString() ?? '0') ?? 0.0,
      weightage: json['weightage'] != null
          ? double.tryParse(json['weightage']?.toString() ?? '1.0')
          : 1.0,
      isPresentation: json['is_presentation'] == 1 ||
                      json['is_presentation'] == true ||
                      json['is_presentation'] == '1',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject_id': subjectId,
      'name': name,
      'max_marks': maxMarks,
      'weightage': weightage,
      'is_presentation': isPresentation ? 1 : 0,
    };
  }
}

// ────────────────────────────────────────────────
// Helper class for criteria scores (used in Assessment)
// ────────────────────────────────────────────────
class CriteriaScore {
  final int criteriaId;
  final String name;
  final double obtained;
  final double max;
  final double percentage;

  CriteriaScore({
    required this.criteriaId,
    required this.name,
    required this.obtained,
    required this.max,
  }) : percentage = max > 0 ? (obtained / max) * 100 : 0.0;

  factory CriteriaScore.fromJson(Map<String, dynamic> json) {
    final scoreStr = json['score']?.toString() ?? json['marks_awarded']?.toString() ?? '0';
    final maxStr   = json['max_marks']?.toString() ?? json['max']?.toString() ?? '0';

    return CriteriaScore(
      criteriaId: int.tryParse(json['criteria_id']?.toString() ?? '0') ?? 0,
      name: json['criteria_name']?.toString() ?? json['name']?.toString() ?? 'Unnamed',
      obtained: double.tryParse(scoreStr) ?? 0.0,
      max: double.tryParse(maxStr) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'criteria_id': criteriaId,
      'criteria_name': name,
      'score': obtained,
      'max_marks': max,
    };
  }
}

class Assessment {
  final int id;
  final int studentId;
  final int subjectId;
  final String studentName;
  final String subjectName;
  final double totalMarks;
  final double maxPossibleMarks;
  final double percentage;
  final String assessmentDate;
  final DateTime createdAt;
  final String? assessorName;
  final int? assessorId;
  final List<CriteriaScore> criteriaScores;

  Assessment({
    required this.id,
    required this.studentId,
    required this.subjectId,
    required this.studentName,
    required this.subjectName,
    required this.totalMarks,
    required this.maxPossibleMarks,
    required this.percentage,
    required this.assessmentDate,
    required this.createdAt,
    this.assessorName,
    this.assessorId,
    List<CriteriaScore>? criteriaScores,
  }) : criteriaScores = criteriaScores ?? [];

  factory Assessment.fromJson(Map<String, dynamic> json) {
    final totalStr  = json['total_marks']?.toString() ?? '0';
    final maxStr    = json['max_possible_marks']?.toString() ?? '0';
    final percStr   = json['percentage']?.toString() ?? '0';

    final criteriaList = (json['criteria_scores'] as List<dynamic>? ?? []).map((e) {
      try {
        return CriteriaScore.fromJson(e as Map<String, dynamic>);
      } catch (err) {
        debugPrint('Failed to parse CriteriaScore: $err - raw: $e');
        return CriteriaScore(
          criteriaId: 0,
          name: 'Parse Error',
          obtained: 0.0,
          max: 0.0,
        );
      }
    }).toList();

    return Assessment(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      studentId: int.tryParse(json['student_id']?.toString() ?? '0') ?? 0,
      subjectId: int.tryParse(json['subject_id']?.toString() ?? '0') ?? 0,
      studentName: json['student_name']?.toString() ?? 'Unknown Student',
      subjectName: json['subject_name']?.toString() ?? 'Unknown Subject',
      totalMarks: double.tryParse(totalStr) ?? 0.0,
      maxPossibleMarks: double.tryParse(maxStr) ?? 0.0,
      percentage: double.tryParse(percStr) ?? 0.0,
      assessmentDate: json['assessment_date']?.toString() ?? DateTime.now().toIso8601String(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      assessorName: json['assessor_name']?.toString() ?? json['assessor_full_name']?.toString(),
      assessorId: int.tryParse(json['assessor_id']?.toString() ?? '0'),
      criteriaScores: criteriaList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student_id': studentId,
      'subject_id': subjectId,
      'student_name': studentName,
      'subject_name': subjectName,
      'total_marks': totalMarks,
      'max_possible_marks': maxPossibleMarks,
      'percentage': percentage,
      'assessment_date': assessmentDate,
      'created_at': createdAt.toIso8601String(),
      'assessor_name': assessorName,
      'assessor_id': assessorId,
      'criteria_scores': criteriaScores.map((c) => c.toJson()).toList(),
    };
  }
}