import 'body_progress_result.dart';
import 'workout_plan_model.dart';

class PlanExerciseStat {
  PlanExerciseStat({
    required this.exercise,
    required this.sessions,
    required this.totalReps,
    this.totalKcal,
  });

  final String exercise;
  final int sessions;
  final int totalReps;
  final double? totalKcal;

  factory PlanExerciseStat.fromJson(Map<String, dynamic> j) {
    return PlanExerciseStat(
      exercise: j['exercise'] as String? ?? '',
      sessions: j['sessions'] as int? ?? 0,
      totalReps: j['total_reps'] as int? ?? 0,
      totalKcal: (j['total_kcal'] as num?)?.toDouble(),
    );
  }
}

class PlanCompletionStats {
  PlanCompletionStats({
    required this.totalSessions,
    required this.totalReps,
    this.totalKcal,
    this.totalDurationSec,
    this.byExercise = const [],
  });

  final int totalSessions;
  final int totalReps;
  final double? totalKcal;
  final int? totalDurationSec;
  final List<PlanExerciseStat> byExercise;

  factory PlanCompletionStats.fromJson(Map<String, dynamic> j) {
    final raw = j['by_exercise'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(PlanExerciseStat.fromJson)
            .toList()
        : <PlanExerciseStat>[];

    return PlanCompletionStats(
      totalSessions: j['total_sessions'] as int? ?? 0,
      totalReps: j['total_reps'] as int? ?? 0,
      totalKcal: (j['total_kcal'] as num?)?.toDouble(),
      totalDurationSec: j['total_duration_sec'] as int?,
      byExercise: list,
    );
  }
}

class PlanCompletionData {
  PlanCompletionData({
    required this.plan,
    required this.stats,
    this.analysis,
  });

  final WorkoutPlanModel plan;
  final PlanCompletionStats stats;
  final BodyProgressResult? analysis;

  factory PlanCompletionData.fromJson(Map<String, dynamic> j) {
    final rawAnalysis = j['analysis'];
    return PlanCompletionData(
      plan: WorkoutPlanModel.fromJson(j['plan'] as Map<String, dynamic>),
      stats: PlanCompletionStats.fromJson(j['stats'] as Map<String, dynamic>),
      analysis: rawAnalysis is Map<String, dynamic>
          ? BodyProgressResult.fromJson(rawAnalysis)
          : null,
    );
  }
}
