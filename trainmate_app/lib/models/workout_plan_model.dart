class WorkoutPlanModel {
  WorkoutPlanModel({
    required this.id,
    required this.name,
    required this.planKind,
    required this.exercises,
    required this.durationWeeks,
    required this.isActive,
    this.templateCategory,
    this.beforePhotoBase64,
    this.afterPhotoBase64,
    this.createdAt,
    this.targetSessions,
    this.sessionsCompleted = 0,
    this.isCompleted = false,
    this.completedAt,
    this.completionPercent,
    this.aiOverallScore,
    this.aiAlignmentPercent,
  });

  final int id;
  final String name;
  final String planKind;
  final String? templateCategory;
  final List<String> exercises;
  final int durationWeeks;
  final String? beforePhotoBase64;
  final String? afterPhotoBase64;
  final bool isActive;
  final String? createdAt;
  final int? targetSessions;
  final int sessionsCompleted;
  final bool isCompleted;
  final String? completedAt;
  final double? completionPercent;
  final double? aiOverallScore;
  final double? aiAlignmentPercent;

  bool get isTemplate => planKind == 'template';
  bool get isCustom => planKind == 'custom';

  bool get isComplete =>
      name.trim().isNotEmpty &&
      exercises.isNotEmpty &&
      durationWeeks >= 4 &&
      durationWeeks <= 12 &&
      beforePhotoBase64 != null &&
      beforePhotoBase64!.trim().isNotEmpty;

  bool get isPlanFinished {
    final target = targetSessions;
    if (target == null || target <= 0 || isCompleted) return false;
    return sessionsCompleted >= target;
  }

  factory WorkoutPlanModel.fromJson(Map<String, dynamic> j) {
    final rawEx = j['exercises'];
    final exercises = rawEx is List
        ? rawEx.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    return WorkoutPlanModel(
      id: j['id'] as int? ?? 0,
      name: j['name'] as String? ?? '',
      planKind: j['plan_kind'] as String? ?? 'custom',
      templateCategory: j['template_category'] as String?,
      exercises: exercises,
      durationWeeks: j['duration_weeks'] as int? ?? 8,
      beforePhotoBase64: j['before_photo_base64'] as String?,
      afterPhotoBase64: j['after_photo_base64'] as String?,
      isActive: j['is_active'] as bool? ?? false,
      createdAt: j['created_at'] as String?,
      targetSessions: j['target_sessions'] as int?,
      sessionsCompleted: j['sessions_completed'] as int? ?? 0,
      isCompleted: j['is_completed'] as bool? ?? false,
      completedAt: j['completed_at'] as String?,
      completionPercent: (j['completion_percent'] as num?)?.toDouble(),
      aiOverallScore: (j['ai_overall_score'] as num?)?.toDouble(),
      aiAlignmentPercent: (j['ai_alignment_percent'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toCreateJson({
    bool? activate,
    bool? onboardingCompleted,
    int? targetSessions,
  }) {
    return {
      'name': name,
      'plan_kind': planKind,
      if (templateCategory != null) 'template_category': templateCategory,
      'exercises': exercises,
      'duration_weeks': durationWeeks,
      if (beforePhotoBase64 != null) 'before_photo_base64': beforePhotoBase64,
      if (afterPhotoBase64 != null) 'after_photo_base64': afterPhotoBase64,
      'target_sessions': ?targetSessions,
      'activate': ?activate,
      'onboarding_completed': ?onboardingCompleted,
    };
  }
}
