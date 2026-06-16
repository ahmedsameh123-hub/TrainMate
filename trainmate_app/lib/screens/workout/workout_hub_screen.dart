import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../core/plan_templates.dart';
import '../../services/app_preferences_service.dart';
import '../../services/app_sync_signal.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/user_service.dart';
import '../../services/workout_service.dart';

class WorkoutHubScreen extends StatefulWidget {
  const WorkoutHubScreen({super.key});

  @override
  State<WorkoutHubScreen> createState() => _WorkoutHubScreenState();
}

class _WorkoutHubScreenState extends State<WorkoutHubScreen> {
  final _workoutService = WorkoutService();
  final _userService = UserService();
  List<WorkoutRow> _recent = const [];
  List<String> _catalog = const [];
  MeData? _me;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primeCachedData();
    AppSyncSignal.refreshTick.addListener(_onGlobalRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  Future<void> _primeCachedData() async {
    final cachedMe = await _userService.getCachedMe();
    final cachedWorkouts = await _workoutService.getCachedWorkouts(limit: 30);
    if (!mounted) return;
    setState(() {
      if (cachedMe != null) _me = cachedMe;
      if (cachedWorkouts.isNotEmpty) _recent = cachedWorkouts;
    });
  }

  Future<void> _load() async {
    final listF = _workoutService.listWorkouts(limit: 30);
    final catalogF = ExerciseCatalogService.instance.getExercises();
    final meF = _userService.getMe();
    List<WorkoutRow>? list;
    List<String>? catalog;
    MeData? me;
    String? loadError;
    try {
      list = await listF.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError = e.toString();
    }
    try {
      catalog = await catalogF.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError ??= e.toString();
    }
    try {
      me = await meF.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError ??= e.toString();
    }
    if (!mounted) return;
    setState(() {
      if (list != null) _recent = list;
      if (catalog != null) _catalog = catalog;
      if (me != null) _me = me;
      _error = loadError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final totalReps = _recent.fold<int>(0, (sum, w) => sum + w.reps);
    final prefs = AppPreferencesService.instance;
    final active = _me?.activePlan;
    final planLabel = active?.name ?? _me?.plan?.category ?? 'Strength';
    final workoutCategory = PlanTemplates.prescriptionCategory(
      active?.templateCategory,
      planLabel,
    );
    final rx = _buildPrescription(
      category: workoutCategory,
      bodyGoal: prefs.bodyGoal,
      defaultRestSec: prefs.restTimerSeconds,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(t.isArabic ? 'Workout' : 'Workout'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t.isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      title: t.isArabic ? 'الجلسات' : 'Sessions',
                      value: '${_recent.length}',
                    ),
                  ),
                  Expanded(
                    child: _MetricTile(
                      title: t.isArabic ? 'العدات' : 'Reps',
                      value: '$totalReps',
                    ),
                  ),
                  Expanded(
                    child: _MetricTile(
                      title: t.isArabic ? 'الكتالوج' : 'Catalog',
                      value: '${_catalog.length}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isArabic ? 'Prescription اليوم' : "Today's Prescription",
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.isArabic
                        ? 'الهدف: ${t.tr('goal.${prefs.bodyGoal}')}  |  ${t.tr('plans.planLabel')}: ${t.categoryLabel(planLabel)}'
                        : 'Goal: ${t.tr('goal.${prefs.bodyGoal}')}  |  ${t.tr('plans.planLabel')}: ${t.categoryLabel(planLabel)}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Sets: ${rx.sets}')),
                      Chip(label: Text('Reps: ${rx.reps}')),
                      Chip(label: Text('Rest: ${rx.restSeconds}s')),
                      Chip(label: Text(rx.intensity)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.pushNamed(context, '/exercise');
              if (mounted) _load();
            },
            icon: const Icon(Icons.videocam_rounded),
            label: Text(t.tr('home.startWorkout')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isArabic ? 'AI Exercise Catalog' : 'AI Exercise Catalog',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _catalog
                        .map(
                          (e) => Chip(
                            avatar: const Icon(Icons.fitness_center_rounded, size: 16),
                            label: Text(
                              ExerciseCatalogService.instance.toDisplayName(e),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.isArabic ? 'آخر الجلسات' : 'Recent Workout Activity',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_recent.isEmpty)
                    Text(t.isArabic ? 'لا يوجد نشاط بعد' : 'No workout activity yet')
                  else
                    ..._recent.take(10).map(
                          (w) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(child: Text('${w.reps}')),
                            title: Text(
                              ExerciseCatalogService.instance.toDisplayName(
                                w.exerciseLabel,
                              ),
                            ),
                            subtitle: Text(
                              '${w.source}${w.durationSec != null ? ' · ${w.durationSec}s' : ''}',
                            ),
                          ),
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
    );
  }
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

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Text(title, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
