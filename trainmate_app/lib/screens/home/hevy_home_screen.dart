import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/workout_service.dart';

class HevyHomeScreen extends StatefulWidget {
  const HevyHomeScreen({super.key});

  @override
  State<HevyHomeScreen> createState() => _HevyHomeScreenState();
}

class _HevyHomeScreenState extends State<HevyHomeScreen> {
  final _workouts = WorkoutService();
  List<WorkoutRow> _recentWorkouts = const [];
  List<String> _modelExercises = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _primeCachedWorkouts();
    _refresh();
  }

  Future<void> _primeCachedWorkouts() async {
    final cached = await _workouts.getCachedWorkouts(limit: 20);
    if (!mounted || cached.isEmpty) return;
    setState(() {
      _recentWorkouts = cached;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final workoutsF = _workouts.listWorkouts(limit: 20);
    final modelExercisesF = ExerciseCatalogService.instance.getExercises();
    List<WorkoutRow>? workouts;
    List<String>? modelExercises;
    String? loadError;
    try {
      workouts = await workoutsF.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError = e.toString();
    }
    try {
      modelExercises = await modelExercisesF.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError ??= e.toString();
    }
    if (!mounted) return;
    setState(() {
      if (workouts != null) _recentWorkouts = workouts;
      if (modelExercises != null) _modelExercises = modelExercises;
      _loading = false;
      _error = loadError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final totalSets = _recentWorkouts.length;
    final totalReps = _recentWorkouts.fold<int>(0, (sum, w) => sum + w.reps);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            Text(
              t.isArabic ? 'سجل التمرين' : 'Workout Logbook',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t.isArabic
                  ? 'واجهة قريبة من Hevy بدون أي جزء اجتماعي'
                  : 'Hevy-style training dashboard without social feed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    title: t.isArabic ? 'الجلسات' : 'Sessions',
                    value: '$totalSets',
                    icon: Icons.fitness_center_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    title: t.isArabic ? 'إجمالي العدات' : 'Total Reps',
                    value: '$totalReps',
                    icon: Icons.repeat_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.isArabic ? 'تمارين موديل الذكاء الاصطناعي' : 'AI Model Exercises',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _modelExercises
                          .map(
                            (e) => Chip(
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
                      t.isArabic ? 'آخر الجلسات' : 'Recent Sessions',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_recentWorkouts.isEmpty)
                      Text(
                        t.isArabic ? 'لا توجد جلسات بعد' : 'No sessions yet',
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      ..._recentWorkouts.take(8).map(
                            (w) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                child: Text('${w.reps}'),
                              ),
                              title: Text(
                                ExerciseCatalogService.instance.toDisplayName(
                                  w.exerciseLabel,
                                ),
                              ),
                              subtitle: Text(w.source),
                              trailing: const Icon(Icons.chevron_right_rounded),
                            ),
                          ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/exercise');
          if (mounted) _refresh();
        },
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(t.isArabic ? 'ابدأ تمرين' : 'Start Workout'),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
