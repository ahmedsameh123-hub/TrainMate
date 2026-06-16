import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class WorkoutSavedResult {
  WorkoutSavedResult({
    required this.row,
    this.sessionReport,
  });

  final WorkoutRow row;
  final String? sessionReport;
}

class WorkoutService {
  static const _workoutsCacheKey = 'trainmate_workouts_cache_v1';

  Future<void> _saveCachedWorkouts(List<dynamic> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_workoutsCacheKey, jsonEncode(list));
  }

  Future<List<WorkoutRow>> getCachedWorkouts({int limit = 50}) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_workoutsCacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WorkoutRow.fromJson(e as Map<String, dynamic>))
          .take(limit)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clearCachedWorkouts() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_workoutsCacheKey);
  }

  Future<WorkoutSavedResult> createWorkout({
    required String exerciseLabel,
    required int reps,
    int? durationSec,
    required String source,
    double? weightKg,
    String? equipment,
    int? sets,
    double? estimatedKcal,
    bool generateAiReport = true,
    String languageCode = 'en',
  }) async {
    final body = <String, dynamic>{
      'exercise_label': exerciseLabel,
      'reps': reps,
      'source': source,
      'generate_ai_report': generateAiReport,
      'languageCode': languageCode,
    };
    if (durationSec != null) body['duration_sec'] = durationSec;
    if (weightKg != null) body['weight_kg'] = weightKg;
    if (equipment != null && equipment.isNotEmpty) {
      body['equipment'] = equipment;
    }
    if (sets != null) body['sets'] = sets;
    if (estimatedKcal != null) body['estimated_kcal'] = estimatedKcal;

    final r = await ApiService.post('/api/workouts', body: body, auth: true);
    if (r.statusCode != 201) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final row = WorkoutRow.fromJson(m);
    final report = m['session_report'] as String?;
    return WorkoutSavedResult(row: row, sessionReport: report);
  }

  Future<List<WorkoutRow>> listWorkouts({int limit = 50}) async {
    final r = await ApiService.get('/api/workouts?limit=$limit');
    if (r.statusCode != 200) {
      throw ApiException(r.statusCode, ApiService.parseErrorBody(r));
    }
    final list = jsonDecode(r.body) as List<dynamic>;
    await _saveCachedWorkouts(list);
    return list
        .map((e) => WorkoutRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class WorkoutRow {
  WorkoutRow({
    required this.id,
    required this.exerciseLabel,
    required this.reps,
    this.durationSec,
    required this.source,
    required this.createdAt,
    this.weightKg,
    this.equipment,
    this.sets,
    this.estimatedKcal,
    this.sessionReport,
  });

  final int id;
  final String exerciseLabel;
  final int reps;
  final int? durationSec;
  final String source;
  final String createdAt;
  final double? weightKg;
  final String? equipment;
  final int? sets;
  final double? estimatedKcal;
  final String? sessionReport;

  factory WorkoutRow.fromJson(Map<String, dynamic> j) {
    return WorkoutRow(
      id: j['id'] as int,
      exerciseLabel: j['exercise_label'] as String,
      reps: j['reps'] as int,
      durationSec: j['duration_sec'] as int?,
      source: j['source'] as String,
      createdAt: j['created_at'] as String? ?? '',
      weightKg: (j['weight_kg'] as num?)?.toDouble(),
      equipment: j['equipment'] as String?,
      sets: j['sets'] as int?,
      estimatedKcal: (j['estimated_kcal'] as num?)?.toDouble(),
      sessionReport: j['session_report'] as String?,
    );
  }
}
