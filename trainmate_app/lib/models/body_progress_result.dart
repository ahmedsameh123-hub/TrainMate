class BodyRegionResult {
  BodyRegionResult({
    required this.id,
    required this.label,
    required this.changePercent,
    required this.score,
    required this.status,
    required this.detail,
  });

  final String id;
  final String label;
  final double changePercent;
  final double score;
  final String status;
  final String detail;

  factory BodyRegionResult.fromJson(Map<String, dynamic> j) {
    return BodyRegionResult(
      id: j['id'] as String? ?? '',
      label: j['label'] as String? ?? '',
      changePercent:
          (j['changePercent'] as num?)?.toDouble() ??
          (j['change_percent'] as num?)?.toDouble() ??
          0,
      score: (j['score'] as num?)?.toDouble() ?? 0,
      status: j['status'] as String? ?? 'unclear',
      detail: j['detail'] as String? ?? '',
    );
  }
}

class BodyProgressResult {
  BodyProgressResult({
    required this.category,
    required this.overallScore,
    required this.planAlignmentPercent,
    required this.planAligned,
    required this.summary,
    required this.regions,
    required this.beforePoseDetected,
    required this.afterPoseDetected,
    this.noMeasurableChange = false,
    this.narrative,
    this.language = 'en',
  });

  final String category;
  final double overallScore;
  final double planAlignmentPercent;
  final bool planAligned;
  final bool noMeasurableChange;
  final String summary;
  final String? narrative;
  final List<BodyRegionResult> regions;
  final bool beforePoseDetected;
  final bool afterPoseDetected;
  final String language;

  factory BodyProgressResult.fromJson(Map<String, dynamic> j) {
    final rawRegions = j['regions'];
    final regions = rawRegions is List
        ? rawRegions
            .whereType<Map<String, dynamic>>()
            .map(BodyRegionResult.fromJson)
            .toList()
        : <BodyRegionResult>[];

    return BodyProgressResult(
      category: j['category'] as String? ?? '',
      overallScore:
          (j['overallScore'] as num?)?.toDouble() ??
          (j['overall_score'] as num?)?.toDouble() ??
          0,
      planAlignmentPercent:
          (j['planAlignmentPercent'] as num?)?.toDouble() ??
          (j['plan_alignment_percent'] as num?)?.toDouble() ??
          0,
      planAligned: j['planAligned'] as bool? ?? j['plan_aligned'] as bool? ?? false,
      noMeasurableChange:
          j['noMeasurableChange'] as bool? ?? j['no_measurable_change'] as bool? ?? false,
      summary: j['summary'] as String? ?? '',
      narrative: j['narrative'] as String?,
      regions: regions,
      beforePoseDetected:
          j['beforePoseDetected'] as bool? ?? j['before_pose_detected'] as bool? ?? true,
      afterPoseDetected:
          j['afterPoseDetected'] as bool? ?? j['after_pose_detected'] as bool? ?? true,
      language: j['language'] as String? ?? 'en',
    );
  }
}
