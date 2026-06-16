import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../services/app_sync_signal.dart';
import '../../models/workout_plan_model.dart';
import '../../services/auth_service.dart';
import '../../services/chatbot_service.dart';
import '../../services/plan_service.dart';
import '../../services/user_service.dart';
import '../../services/workout_service.dart';
import '../plans/plan_completion_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _user = UserService();
  final _auth = AuthService();
  final _workouts = WorkoutService();
  final _plans = PlanService();
  final _chatbot = ChatbotService();
  MeData? _me;
  List<WorkoutRow> _history = const [];
  List<WorkoutPlanModel> _completedPlans = const [];
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
    final cached = await _workouts.getCachedWorkouts(limit: 40);
    if (!mounted || cached.isEmpty) return;
    setState(() => _history = cached);
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

  Future<void> _load() async {
    final lang = Localizations.localeOf(context).languageCode;
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }
    final meFuture = _user.getMe();
    final workoutsFuture = _workouts.listWorkouts(limit: 40);
    MeData? me;
    List<WorkoutRow>? history;
    String? loadError;

    try {
      me = await meFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError = e.toString();
    }
    try {
      history = await workoutsFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError ??= e.toString();
    }

    List<WorkoutPlanModel> completed = const [];
    try {
      completed = await _plans.listCompletedPlans();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      if (me != null) _me = me;
      if (history != null) _history = history;
      _completedPlans = completed;
      _error = loadError;
      _loading = false;
    });

    try {
      final coach = await _chatbot.progressFeedback(
        userId: me?.id ?? _me?.id,
        languageCode: lang,
      );
      if (!mounted) return;
      setState(() => _coachFeedback = coach);
    } catch (_) {}
  }

  Future<void> _logout() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppText.of(context);
    final totalReps = _history.fold<int>(0, (sum, w) => sum + w.reps);
    final sessions = _history.length;
    final level = (sessions ~/ 5) + 1;
    final progressToNext = ((sessions % 5) / 5).clamp(0.0, 1.0);
    final totalKcal = _history.fold<double>(
      0,
      (sum, w) => sum + (w.estimatedKcal ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tr('profile.title')),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              if (mounted) _load();
            },
            tooltip: t.tr('settings.title'),
            icon: const Icon(Icons.settings_rounded),
          ),
          IconButton(
            onPressed: _logout,
            tooltip: t.tr('profile.signOut'),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _me == null && _history.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_me != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundImage: _me!.profile?.profileImageBase64 != null &&
                                _me!.profile!.profileImageBase64!.isNotEmpty
                            ? MemoryImage(
                                base64Decode(_me!.profile!.profileImageBase64!),
                              )
                            : null,
                        child: _me!.profile?.profileImageBase64 == null ||
                                _me!.profile!.profileImageBase64!.isEmpty
                            ? Text(
                                ((_me!.name ?? _me!.email).trim().isNotEmpty
                                        ? (_me!.name ?? _me!.email).trim()[0]
                                        : 'U')
                                    .toUpperCase(),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_me!.name ?? 'User', style: theme.textTheme.titleMedium),
                            Text(
                              _me!.email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.insights_rounded,
                            color: cs.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          t.tr('home.performanceDashboard'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.2,
                      children: [
                        _ProfileMetric(
                          icon: Icons.fitness_center_rounded,
                          label: 'Sessions',
                          value: '$sessions',
                        ),
                        _ProfileMetric(
                          icon: Icons.repeat_rounded,
                          label: 'Total Reps',
                          value: '$totalReps',
                        ),
                        _ProfileMetric(
                          icon: Icons.local_fire_department_rounded,
                          label: t.tr('home.metricCalories'),
                          value: totalKcal > 0 ? totalKcal.toStringAsFixed(0) : '—',
                        ),
                        _ProfileMetric(
                          icon: Icons.rocket_launch_rounded,
                          label: 'Level',
                          value: 'L$level',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: progressToNext,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          t.tr('home.progressToNextLevel'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${(progressToNext * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(height: 120, child: _MiniBars(history: _history)),
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
                      t.tr('profile.completedPlans'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_completedPlans.isEmpty)
                      Text(
                        t.tr('profile.noCompletedPlans'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else
                      ..._completedPlans.map((plan) => _completedPlanTile(plan, t, theme)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('home.feedbackTitle'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _loading
                          ? t.tr('common.loading')
                          : (_coachFeedback?.trim().isNotEmpty == true
                              ? _coachFeedback!
                              : t.tr('home.feedbackNone')),
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
    );
  }

  String _formatCompletedDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  Future<void> _openCompletedPlan(WorkoutPlanModel plan) async {
    try {
      final data = await _plans.getPlanCompletion(plan.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlanCompletionScreen(
            plan: plan,
            initialData: data,
            readOnly: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _completedPlanTile(WorkoutPlanModel plan, AppText t, ThemeData theme) {
    final pct = plan.completionPercent?.toStringAsFixed(0) ?? '—';
    final ai = plan.aiOverallScore?.toStringAsFixed(0);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.check_circle, color: theme.colorScheme.primary),
      ),
      title: Text(plan.name),
      subtitle: Text(
        '${t.tr('profile.completedOn', args: {'date': _formatCompletedDate(plan.completedAt)})}\n'
        '${t.tr('planComplete.completionRate')}: $pct%'
        '${ai != null ? ' · ${t.tr('planComplete.improvementRate')}: $ai/100' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openCompletedPlan(plan),
    );
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: theme.textTheme.labelSmall),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.history});

  final List<WorkoutRow> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = history.take(7).toList().reversed.toList();
    if (recent.isEmpty) {
      return Center(
        child: Text(
          AppText.of(context).tr('home.noData'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final maxReps = recent.map((e) => e.reps).reduce((a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: recent
          .map(
            (w) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${w.reps}', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Container(
                      height: ((w.reps / (maxReps == 0 ? 1 : maxReps)) * 70).clamp(
                        8,
                        70,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
