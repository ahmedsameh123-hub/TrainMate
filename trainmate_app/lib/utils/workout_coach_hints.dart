/// Short live coaching lines keyed by normalized exercise id (lowercase slug).
String liveFormHintForExercise(String rawLabel, {required bool arabic}) {
  final key = rawLabel.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  final id = _normalizeExerciseKey(key);
  final en = _hintsEn[id] ?? _hintsEn['default']!;
  final ar = _hintsAr[id] ?? _hintsAr['default']!;
  return arabic ? ar : en;
}

String _normalizeExerciseKey(String key) {
  if (key.contains('push')) return 'push-up';
  if (key.contains('squat')) return 'squat';
  if (key.contains('curl') || key.contains('bicep')) return 'curl';
  if (key.contains('shoulder') && key.contains('press')) return 'shoulder press';
  if (key.contains('deadlift')) return 'deadlift';
  if (key.contains('bench')) return 'bench press';
  return key;
}

const Map<String, String> _hintsEn = {
  'push-up':
      'Keep ribs down, glutes tight; elbows ~45°; full range without sagging hips.',
  'squat':
      'Feet planted, knees track toes; chest tall; depth you control with neutral spine.',
  'curl':
      'Elbows fixed at sides — move the forearm only; no swinging the torso.',
  'shoulder press':
      'Brace core; press overhead in a slight arc; avoid excessive lower-back arch.',
  'deadlift':
      'Hinge at hips, bar close to shins; neutral spine; drive with legs first.',
  'bench press':
      'Stable shoulder blades, slight arch acceptable; bar path not straight vertical.',
  'default':
      'Move with control, breathe steadily, and stop if sharp joint pain appears.',
};

const Map<String, String> _hintsAr = {
  'push-up':
      'ثبّت الكور والأرداف؛ المرفقان بزاوية ~45°؛ نطاق كامل بدون هبوط الحوض.',
  'squat':
      'وزن القدم كامل؛ الركبتان باتجاه أصابع القدم؛ صدر مرفوع وظهر محايد.',
  'curl':
      'ثبّت المرفقين على الجنب — حرّك الساعد فقط بدون تأرجح الجذع.',
  'shoulder press':
      'شدّ البطن؛ ادفع للأعلى بقوس بسيط؛ تجنّب انحناء أسفل الظهر الزائد.',
  'deadlift':
      'مفصل الورك، البار قريب من الساقين؛ ظهر محايد؛ ابدأ بالدفع من الرجلين.',
  'bench press':
      'لوح الكتف ثابت؛ قوس بسيط مقبول؛ مسار البار ليس عمودياً تماماً.',
  'default':
      'تحرّك بتحكم وتنفّس بانتظام؛ توقّف عند أي ألم حاد في المفصل.',
};

/// Rough MET-based kcal for the session (same idea as server).
double? estimateSessionKcal({
  required String exerciseLabel,
  required double? userBodyWeightKg,
  required double? extraLoadKg,
  required int reps,
  required int sets,
  required int durationSec,
}) {
  if (durationSec <= 0) return null;
  final bodyWeight = userBodyWeightKg;
  if (bodyWeight == null || bodyWeight <= 0) return null;

  // Effective system mass: bodyweight + a bounded portion of external load.
  final load = (extraLoadKg != null && extraLoadKg > 0)
      ? extraLoadKg.clamp(0, bodyWeight * 1.25)
      : 0.0;
  final effectiveMassKg = bodyWeight + (load * 0.65);

  // Heuristic active ratio: more sets/reps increases "work" share of session time.
  final boundedSets = sets.clamp(1, 30);
  final boundedReps = reps.clamp(0, 400);
  final volumeSignal = ((boundedSets * boundedReps) / 180.0).clamp(0.0, 1.0);
  final activeRatio = (0.38 + (volumeSignal * 0.32)).clamp(0.35, 0.75);

  final met = _metForLabel(exerciseLabel);
  return met * activeRatio * effectiveMassKg * (durationSec / 3600.0);
}

double _metForLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('push')) return 3.8;
  if (l.contains('squat')) return 5.0;
  if (l.contains('curl') || l.contains('bicep')) return 3.5;
  if (l.contains('deadlift')) return 6.0;
  if (l.contains('bench') || l.contains('press') || l.contains('shoulder')) {
    return 4.0;
  }
  return 4.0;
}
