import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/app_preferences_service.dart';
import '../../core/plan_templates.dart';
import '../../services/app_sync_signal.dart';
import '../../services/auth_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/user_service.dart';
import '../../services/workout_service.dart';

class SmartHomeScreen extends StatefulWidget {
  const SmartHomeScreen({super.key});

  @override
  State<SmartHomeScreen> createState() => _SmartHomeScreenState();
}

class _SmartHomeScreenState extends State<SmartHomeScreen> {
  final _auth = AuthService();
  final _user = UserService();
  final _workouts = WorkoutService();
  final _chatbot = ChatbotService();
  MeData? _me;
  List<WorkoutRow> _recent = const [];
  final List<String> _modelExercises = const [
    'push-up',
    'squat',
    'barbell biceps curl',
    'shoulder press',
  ];
  String? _coachFeedback;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _primeCachedMe();
    _primeCachedWorkouts();
    AppSyncSignal.refreshTick.addListener(_onGlobalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _primeCachedCoachFeedback();
      _load();
    });
  }

  @override
  void dispose() {
    AppSyncSignal.refreshTick.removeListener(_onGlobalRefresh);
    super.dispose();
  }

  void _onGlobalRefresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _primeCachedMe() async {
    final cached = await _user.getCachedMe();
    if (!mounted || cached == null) return;
    setState(() => _me = cached);
  }

  Future<void> _primeCachedWorkouts() async {
    final cached = await _workouts.getCachedWorkouts(limit: 20);
    if (!mounted || cached.isEmpty) return;
    setState(() => _recent = cached);
  }

  Future<void> _primeCachedCoachFeedback() async {
    final lang = Localizations.localeOf(context).languageCode;
    final me = _me ?? await _user.getCachedMe();
    final cached = await _chatbot.getCachedProgressFeedback(
      userId: me?.id,
      languageCode: lang,
    );
    if (!mounted || cached == null || cached.trim().isEmpty) return;
    setState(() => _coachFeedback = cached.trim());
  }

  bool _looksArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  String _cleanReportText(String text) {
    return text
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[#*•]+'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _fallbackSessionReport(WorkoutRow workout, String languageCode) {
    final duration = workout.durationSec == null
        ? (languageCode == 'ar' ? 'غير محددة' : 'Not specified')
        : languageCode == 'ar'
        ? '${workout.durationSec! ~/ 60} دقيقة ${workout.durationSec! % 60} ثانية'
        : '${workout.durationSec! ~/ 60} min ${workout.durationSec! % 60} sec';
    final sets = workout.sets?.toString() ??
        (languageCode == 'ar' ? 'غير محدد' : 'Not specified');
    final kcal = workout.estimatedKcal == null
        ? (languageCode == 'ar' ? 'غير متاح' : 'Not available')
        : workout.estimatedKcal!.round().toString();
    if (languageCode == 'ar') {
      return '''
ملخص الجلسة
التمرين: ${workout.exerciseLabel}
التكرارات: ${workout.reps}
المدة: $duration
الجولات: $sets
السعرات التقديرية: $kcal
'''.trim();
    }
    return '''
Session summary
Exercise: ${workout.exerciseLabel}
Reps: ${workout.reps}
Duration: $duration
Sets: $sets
Estimated calories: $kcal
'''.trim();
  }

  String? _lastSessionReport() {
    final languageCode = Localizations.localeOf(context).languageCode;
    for (final w in _recent) {
      final r = w.sessionReport?.trim();
      if (r == null || r.isEmpty) continue;
      final clean = _cleanReportText(r);
      if (languageCode == 'en' && _looksArabic(clean)) {
        return _fallbackSessionReport(w, languageCode);
      }
      if (languageCode == 'ar' && !_looksArabic(clean)) {
        return _fallbackSessionReport(w, languageCode);
      }
      return clean;
    }
    return null;
  }

  List<String> _reportHighlights(String report) {
    final clean = _cleanReportText(report);
    final parts = clean
        .split(RegExp(r'[\n•\-]+'))
        .map((e) => e.trim())
        .where((e) => e.length > 6)
        .toList();
    if (parts.isEmpty) return [clean];
    return parts.take(4).toList();
  }

  Future<void> _load() async {
    final lang = Localizations.localeOf(context).languageCode;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final meFuture = _user.getMe();
    final workoutsFuture = _workouts.listWorkouts(limit: 20);
    MeData? me;
    List<WorkoutRow>? workouts;
    String? loadError;

    try {
      me = await meFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      if (AuthService.isUnauthorizedError(e)) {
        await _auth.invalidateSession();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
      loadError = e.toString();
    }
    try {
      workouts = await workoutsFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      if (AuthService.isUnauthorizedError(e)) {
        await _auth.invalidateSession();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
        return;
      }
      loadError ??= e.toString();
    }

    if (!mounted) return;
    setState(() {
      if (me != null) _me = me;
      if (workouts != null) _recent = workouts;
      _error = loadError;
      _loading = false;
    });

    try {
      final feedback = await _chatbot.progressFeedback(
        userId: me?.id ?? _me?.id,
        languageCode: lang,
      );
      if (!mounted) return;
      setState(() => _coachFeedback = feedback);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final name = _me?.name?.trim().isNotEmpty == true
        ? _me!.name!.trim()
        : t.tr('home.athlete');
    final plan = _me?.plan;
    final planLabel = _me?.activePlan?.name ?? plan?.category;
    final planWeeks = _me?.activePlan?.durationWeeks ?? plan?.durationWeeks;
    final doneCount = _recent.length;
    final weeklyTarget = math.max((planWeeks ?? plan?.durationWeeks ?? 8) ~/ 2, 4);
    final needed = (weeklyTarget - doneCount).clamp(0, weeklyTarget);
    final workflowDays = _buildWorkflowDays();
    final prefs = AppPreferencesService.instance;

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
            _SmartHeroHeader(
              name: name,
              plan: plan,
              planLabel: planLabel,
              planWeeks: planWeeks,
              doneCount: doneCount,
              needed: needed,
              theme: theme,
              t: t,
              onStart: () async {
                await Navigator.pushNamed(context, '/exercise');
                if (mounted) _load();
              },
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.isArabic ? 'Workout Flow الاسبوعي' : 'Weekly Workout Flow',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    ...workflowDays.map(
                      (day) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_rounded),
                        title: Text(day.label),
                        subtitle: Text([
                          day.exercises.join('  •  '),
                          if (day.sets > 0)
                            'Sets: ${day.sets}  |  Reps: ${day.reps}  |  Rest: ${day.restSeconds}s  |  ${day.intensity}',
                        ].join('\n')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.isArabic ? 'خطة اليوم السريعة' : 'Today Quick Checklist',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('• ${t.isArabic ? 'إحماء 8-10 دقائق' : '8-10 min warm-up'}'),
                    Text('• ${t.isArabic ? 'تنفيذ 4-6 جولات أساسية' : 'Execute 4-6 primary sets'}'),
                    Text(
                      '• ${t.isArabic ? 'راحة افتراضية' : 'Default rest'}: ${prefs.restTimerSeconds}s',
                    ),
                    Text('• ${t.isArabic ? 'إنهاء وتمدد خفيف' : 'Finish with cool-down and stretch'}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_lastSessionReport() != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.description_rounded,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            t.tr('home.lastSessionReport'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _reportHighlights(_lastSessionReport()!)
                              .map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          line,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            height: 1.35,
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.isArabic ? 'Coach Insight' : 'Coach Insight',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loading
                          ? t.tr('common.loading')
                          : (_coachFeedback?.trim().isNotEmpty == true
                              ? _coachFeedback!
                              : (t.isArabic
                                    ? 'حافظ على ثبات الأداء وزود الحمل تدريجيا.'
                                    : 'Keep your form strict and apply progressive overload.')),
                    ),
                    const SizedBox(height: 10),
                    if (prefs.chatbotWatermark)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified_rounded, size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              t.isArabic ? 'AI Coach Signature' : 'AI Coach Signature',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pushNamed(context, '/chatbot'),
                            icon: const Icon(Icons.smart_toy_rounded),
                            label: Text(t.tr('home.coachChat')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/settings/chatbot'),
                          icon: const Icon(Icons.tune_rounded),
                          tooltip: t.tr('settings.chatbotSettings'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
              ],
            ),
          ),
          if (prefs.chatbotWatermark)
            Positioned(
              right: 14,
              bottom: 16,
              child: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/chatbot'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        t.isArabic ? 'AI Coach' : 'AI Coach',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_WorkflowDay> _buildWorkflowDays() {
    final now = DateTime.now();
    final labels = AppText.of(context).isArabic
        ? const ['اليوم', 'غدا', 'بعده', 'اليوم 4', 'اليوم 5']
        : const ['Today', 'Tomorrow', 'Day 3', 'Day 4', 'Day 5'];
    final prefs = AppPreferencesService.instance;
    final active = _me?.activePlan;
    final planName = active?.name ?? _me?.plan?.category ?? 'Strength';
    final workoutCategory = PlanTemplates.prescriptionCategory(
      active?.templateCategory,
      planName,
    );
    final planExercises = active?.exercises ?? const <String>[];
    final pool = planExercises.isNotEmpty
        ? planExercises
        : _goalDrivenPool(
            category: workoutCategory,
            bodyGoal: prefs.bodyGoal,
            history: _recent,
          );
    final trainingDays = prefs.trainingDaysPerWeek.clamp(2, 5);
    final prescription = _buildPrescription(
      category: workoutCategory,
      bodyGoal: prefs.bodyGoal,
      defaultRestSec: prefs.restTimerSeconds,
    );
    return List.generate(5, (i) {
      final day = now.add(Duration(days: i));
      final isRest = i >= trainingDays;
      final selected = isRest
          ? <String>[
              AppText.of(context).isArabic
                  ? 'نشاط خفيف + تمارين مرونة'
                  : 'Light activity + mobility',
            ]
          : List.generate(3, (j) {
              final idx = (i * 3 + j) % pool.length;
              return pool[idx];
            });
      final title = '${labels[i]} (${day.day}/${day.month})';
      return _WorkflowDay(
        label: title,
        exercises: selected,
        sets: isRest ? 0 : prescription.sets,
        reps: isRest ? (AppText.of(context).isArabic ? 'استشفاء' : 'Recovery') : prescription.reps,
        restSeconds: isRest ? 0 : prescription.restSeconds,
        intensity: isRest
            ? (AppText.of(context).isArabic ? 'خفيف' : 'Light')
            : prescription.intensity,
      );
    });
  }

  List<String> _goalDrivenPool({
    required String category,
    required String bodyGoal,
    required List<WorkoutRow> history,
  }) {
    final byCategory = PlanTemplates.exercisesByTemplate;

    final byGoal = <String, List<String>>{
      'fat_loss': PlanTemplates.exercisesFor('Weight Loss'),
      'muscle_building': PlanTemplates.exercisesFor('Muscle Gain'),
      'strength_performance': PlanTemplates.exercisesFor('Strength'),
      'body_recomposition': PlanTemplates.exercisesFor('Muscle Gain'),
      'balanced_fitness': PlanTemplates.supportedExercises,
    };

    final recent = history.map((e) => e.exerciseLabel.toLowerCase()).toSet();
    final combined = [
      ...?byCategory[category],
      ...?byGoal[bodyGoal],
      ..._modelExercises,
    ]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    combined.sort((a, b) {
      final aRecent = recent.contains(a.toLowerCase()) ? 1 : 0;
      final bRecent = recent.contains(b.toLowerCase()) ? 1 : 0;
      return aRecent.compareTo(bRecent);
    });
    return combined.isEmpty ? _modelExercises : combined;
  }

  _WorkoutPrescription _buildPrescription({
    required String category,
    required String bodyGoal,
    required int defaultRestSec,
  }) {
    final key = '$category::$bodyGoal';
    switch (key) {
      case 'Strength::strength_performance':
        return _WorkoutPrescription(
          sets: 5,
          reps: '3-5',
          restSeconds: (defaultRestSec + 60).clamp(60, 240),
          intensity: 'RPE 8-9',
        );
      case 'Muscle Gain::muscle_building':
        return _WorkoutPrescription(
          sets: 4,
          reps: '8-12',
          restSeconds: defaultRestSec.clamp(60, 120),
          intensity: 'RPE 7-8',
        );
      case 'Weight Loss::fat_loss':
        return _WorkoutPrescription(
          sets: 3,
          reps: '12-18',
          restSeconds: (defaultRestSec - 20).clamp(30, 90),
          intensity: 'RPE 7',
        );
      case 'Endurance::balanced_fitness':
      case 'Endurance::body_recomposition':
        return _WorkoutPrescription(
          sets: 3,
          reps: '15-20',
          restSeconds: (defaultRestSec - 15).clamp(30, 90),
          intensity: 'RPE 6-7',
        );
      case 'Mobility::balanced_fitness':
        return _WorkoutPrescription(
          sets: 2,
          reps: '40-60 sec',
          restSeconds: 30,
          intensity: 'Easy',
        );
      default:
        return _WorkoutPrescription(
          sets: 4,
          reps: '8-12',
          restSeconds: defaultRestSec.clamp(45, 150),
          intensity: 'RPE 7-8',
        );
    }
  }
}

class _SmartHeroHeader extends StatelessWidget {
  const _SmartHeroHeader({
    required this.name,
    required this.plan,
    required this.planLabel,
    required this.planWeeks,
    required this.doneCount,
    required this.needed,
    required this.theme,
    required this.t,
    required this.onStart,
  });

  final String name;
  final UserPlanData? plan;
  final String? planLabel;
  final int? planWeeks;
  final int doneCount;
  final int needed;
  final ThemeData theme;
  final AppText t;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.28),
                cs.tertiary.withValues(alpha: 0.22),
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'TrainMate',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.trending_up_rounded, color: cs.onPrimaryContainer.withValues(alpha: 0.9)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                t.isArabic ? 'أهلًا، $name' : 'Hey, $name',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t.isArabic
                    ? 'خطتك جاهزة — اضغط وابدأ جلستك.'
                    : 'Your plan is ready — tap and start your session.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.88),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t.tr(
                  'home.planLine',
                  args: {
                    'category': planLabel == null || planLabel!.trim().isEmpty
                        ? t.tr('home.notSet')
                        : t.categoryLabel(planLabel!),
                    'weeks': '${planWeeks ?? "-"}',
                  },
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 18),
              Material(
                color: cs.primary,
                borderRadius: BorderRadius.circular(16),
                elevation: 3,
                shadowColor: cs.primary.withValues(alpha: 0.45),
                child: InkWell(
                  onTap: onStart,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 26),
                        const SizedBox(width: 10),
                        Text(
                          t.isArabic ? 'ابدأ التمرين الآن' : 'Start workout now',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _DashMiniStat(
                theme: theme,
                icon: Icons.fitness_center_rounded,
                value: '$doneCount',
                label: t.isArabic ? 'جلسات' : 'Sessions',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DashMiniStat(
                theme: theme,
                icon: Icons.flag_circle_outlined,
                value: '$needed',
                label: t.isArabic ? 'متبقي أسبوعيًا' : 'Weekly left',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashMiniStat extends StatelessWidget {
  const _DashMiniStat({
    required this.theme,
    required this.icon,
    required this.value,
    required this.label,
  });

  final ThemeData theme;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowDay {
  _WorkflowDay({
    required this.label,
    required this.exercises,
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.intensity,
  });

  final String label;
  final List<String> exercises;
  final int sets;
  final String reps;
  final int restSeconds;
  final String intensity;
}

class _WorkoutPrescription {
  _WorkoutPrescription({
    required this.sets,
    required this.reps,
    required this.restSeconds,
    required this.intensity,
  });

  final int sets;
  final String reps;
  final int restSeconds;
  final String intensity;
}
