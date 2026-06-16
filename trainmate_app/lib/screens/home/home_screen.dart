import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;

import '../../l10n/app_text.dart';
import '../../services/chatbot_service.dart';
import '../../services/notification_service.dart';
import '../../services/user_service.dart';
import '../../services/workout_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _user = UserService();
  final _workouts = WorkoutService();
  final _chatbot = ChatbotService();
  MeData? _me;
  List<WorkoutRow> _recentWorkouts = const [];
  String? _loadError;
  bool _weeklyChart = true;
  String? _coachFeedback;

  @override
  void initState() {
    super.initState();
    _primeCachedData();
    _refresh();
  }

  Future<void> _primeCachedData() async {
    final cachedMe = await _user.getCachedMe();
    final cachedWorkouts = await _workouts.getCachedWorkouts(limit: 30);
    if (!mounted) return;
    setState(() {
      if (cachedMe != null) _me = cachedMe;
      if (cachedWorkouts.isNotEmpty) _recentWorkouts = cachedWorkouts;
    });
  }

  Future<void> _refresh() async {
    final workoutsFuture = _workouts.listWorkouts(limit: 30);
    final meFuture = _user.getMe();
    MeData? me;
    List<WorkoutRow>? workouts;
    String? loadError;
    try {
      me = await meFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError = e.toString();
    }
    try {
      workouts = await workoutsFuture.timeout(const Duration(seconds: 8));
    } catch (e) {
      loadError ??= e.toString();
    }
    if (!mounted) return;
    setState(() {
      if (me != null) _me = me;
      if (workouts != null) _recentWorkouts = workouts;
      _loadError = loadError;
    });
    if (me != null && workouts != null) {
      _maybeNotify(me, workouts);
    }
    try {
      final aiFeedback = await _chatbot.progressFeedback(
        userId: me?.id ?? _me?.id,
        languageCode: AppText.of(context).languageCode,
      );
      if (mounted && aiFeedback.trim().isNotEmpty) {
        setState(() => _coachFeedback = aiFeedback.trim());
      }
    } catch (_) {}
  }

  Future<void> _maybeNotify(MeData me, List<WorkoutRow> workouts) async {
    final t = AppText.of(context);
    final insights = _WorkoutInsights.from(workouts, t);
    final planWeeks = me.plan?.durationWeeks ?? 8;
    final progress = (insights.totalSessions / (planWeeks * 4)).clamp(0, 1);

    if (await NotificationService.instance.shouldSendToday('daily_workout')) {
      await NotificationService.instance.sendNow(
        title: t.isArabic ? 'تذكير تمرين اليوم' : 'Today workout reminder',
        body: t.isArabic
            ? 'متبقي ${(100 - (progress * 100)).round()}% لإنهاء الخطة. يلا تمرين!'
            : '${(100 - (progress * 100)).round()}% left to complete your plan. Let us train!',
        kind: 'daily',
      );
    }

    if (await NotificationService.instance.shouldSendToday('feedback')) {
      await NotificationService.instance.sendNow(
        title: t.isArabic ? 'ملخص الأداء' : 'Performance feedback',
        body: insights.feedback,
        kind: 'feedback',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    final p = _me?.profile;
    final plan = _me?.plan;
    final profileIncomplete = p == null || !p.isComplete;
    final displayName = _me?.name?.trim().isNotEmpty == true
        ? _me!.name!
        : t.tr('home.athlete');
    final insights = _WorkoutInsights.from(_recentWorkouts, t);
    final profileImage = _me?.profile?.profileImageBase64;
    final totalReps = insights.totalReps;
    final sessions = insights.totalSessions;
    final weeklyTarget = plan?.durationWeeks != null ? 20 : 12;
    final progressValue = (sessions / weeklyTarget).clamp(0, 1).toDouble();
    final feedback = insights.feedback;
    final showFeedback = (_coachFeedback?.trim().isNotEmpty == true) ? _coachFeedback! : feedback;
    final chartBars = _weeklyChart ? insights.weeklyBars : insights.monthlyBars;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/chatbot'),
        icon: const Icon(Icons.smart_toy_rounded),
        label: Text(t.tr('home.coachChat')),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: theme.colorScheme.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: profileImage != null && profileImage.isNotEmpty
                      ? MemoryImage(base64Decode(profileImage))
                      : null,
                  child: profileImage == null || profileImage.isEmpty
                      ? Text(displayName.substring(0, 1).toUpperCase())
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('home.welcome', args: {'name': displayName}),
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        t.tr('home.tagline'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/notifications/history'),
                  icon: const Icon(Icons.notifications_none_rounded),
                  tooltip: t.tr('home.notifications'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CustomPaint(
                        painter: _ProgressRingPainter(
                          value: progressValue,
                          color: theme.colorScheme.primary,
                          bg: theme.colorScheme.surfaceContainerHighest,
                        ),
                        child: Center(
                          child: Text(
                            '${(progressValue * 100).round()}%',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.tr('home.workoutProgress'),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.tr('home.sessions', args: {'value': '$sessions'}),
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            t.tr(
                              'home.totalReps',
                              args: {'value': '$totalReps'},
                            ),
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            t.tr(
                              'home.planLine',
                              args: {
                                'category': plan?.category == null
                                    ? t.tr('home.notSet')
                                    : t.categoryLabel(plan!.category!),
                                'weeks': '${plan?.durationWeeks ?? "-"}',
                              },
                            ),
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
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.45,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.tr('home.feedbackTitle'),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(showFeedback, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    Text(
                      t.tr(
                        'home.topExercise',
                        args: {
                          'exercise': insights.topExercise,
                          'avg': insights.avgRepsPerSession.toStringAsFixed(1),
                        },
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
                        Text(
                          t.tr('home.trainingChart'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const Spacer(),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment<bool>(
                              value: true,
                              label: Text(t.tr('home.weekly')),
                            ),
                            ButtonSegment<bool>(
                              value: false,
                              label: Text(t.tr('home.monthly')),
                            ),
                          ],
                          selected: {_weeklyChart},
                          onSelectionChanged: (v) =>
                              setState(() => _weeklyChart = v.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 190,
                      child: _BarsChart(
                        bars: chartBars,
                        maxValue: _WorkoutInsights.maxBarValue(chartBars),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_loadError != null)
              Text(
                _loadError!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (profileIncomplete) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/onboarding'),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(t.tr('home.completeSetup')),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.pushNamed(context, '/exercise');
                if (mounted) _refresh();
              },
              icon: const Icon(Icons.videocam_rounded),
              label: Text(t.tr('home.startWorkout')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 54),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.value,
    required this.color,
    required this.bg,
  });

  final double value;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final basePaint = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    final fgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;

    canvas.drawCircle(center, radius, basePaint);
    final sweep = value.clamp(0, 1) * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.bg != bg;
  }
}

class _WorkoutInsights {
  _WorkoutInsights({
    required this.totalSessions,
    required this.totalReps,
    required this.avgRepsPerSession,
    required this.topExercise,
    required this.feedback,
    required this.weeklyBars,
    required this.monthlyBars,
  });

  final int totalSessions;
  final int totalReps;
  final double avgRepsPerSession;
  final String topExercise;
  final String feedback;
  final List<_ChartBarPoint> weeklyBars;
  final List<_ChartBarPoint> monthlyBars;

  static double maxBarValue(List<_ChartBarPoint> bars) {
    if (bars.isEmpty) return 1;
    final maxV = bars.map((e) => e.value).reduce(math.max);
    return maxV <= 0 ? 1 : maxV;
  }

  static _WorkoutInsights from(List<WorkoutRow> workouts, AppText t) {
    final sorted = [...workouts]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final totalReps = sorted.fold<int>(0, (sum, w) => sum + w.reps);
    final sessions = sorted.length;
    final avg = sessions == 0 ? 0.0 : totalReps / sessions;

    final perExercise = <String, int>{};
    for (final w in sorted) {
      perExercise[w.exerciseLabel] = (perExercise[w.exerciseLabel] ?? 0) + 1;
    }
    var top = t.tr('home.noData');
    if (perExercise.isNotEmpty) {
      final list = perExercise.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      top = list.first.key;
    }

    final now = DateTime.now();
    final weekly = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      final v = sorted
          .where((w) {
            final d = DateTime.tryParse(w.createdAt)?.toLocal();
            return d != null &&
                d.year == day.year &&
                d.month == day.month &&
                d.day == day.day;
          })
          .fold<int>(0, (sum, e) => sum + e.reps);
      final labels = t.isArabic
          ? const ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح']
          : const ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      return _ChartBarPoint(
        label: labels[day.weekday - 1],
        value: v.toDouble(),
      );
    });

    final monthly = List.generate(4, (i) {
      final end = now.subtract(Duration(days: (3 - i) * 7));
      final start = end.subtract(const Duration(days: 6));
      final v = sorted
          .where((w) {
            final d = DateTime.tryParse(w.createdAt)?.toLocal();
            return d != null &&
                !d.isBefore(DateTime(start.year, start.month, start.day)) &&
                !d.isAfter(end);
          })
          .fold<int>(0, (sum, e) => sum + e.reps);
      return _ChartBarPoint(
        label: t.isArabic ? 'أ${i + 1}' : 'W${i + 1}',
        value: v.toDouble(),
      );
    });

    String feedback;
    if (sessions == 0) {
      feedback = t.tr('home.feedbackNone');
    } else {
      final firstHalf = sorted
          .take((sessions / 2).ceil())
          .fold<int>(0, (s, e) => s + e.reps);
      final secondHalf = sorted
          .skip((sessions / 2).ceil())
          .fold<int>(0, (s, e) => s + e.reps);
      final trendUp = secondHalf >= firstHalf;
      final lastDate = DateTime.tryParse(sorted.last.createdAt)?.toLocal();
      final inactiveDays = lastDate == null
          ? 99
          : now.difference(lastDate).inDays;
      if (inactiveDays >= 5) {
        feedback = t.tr(
          'home.feedbackInactive',
          args: {'days': '$inactiveDays'},
        );
      } else if (trendUp) {
        feedback = t.tr('home.feedbackUp');
      } else {
        feedback = t.tr('home.feedbackDown');
      }
    }

    return _WorkoutInsights(
      totalSessions: sessions,
      totalReps: totalReps,
      avgRepsPerSession: avg,
      topExercise: top,
      feedback: feedback,
      weeklyBars: weekly,
      monthlyBars: monthly,
    );
  }
}

class _ChartBarPoint {
  _ChartBarPoint({required this.label, required this.value});
  final String label;
  final double value;
}

class _BarsChart extends StatelessWidget {
  const _BarsChart({required this.bars, required this.maxValue});

  final List<_ChartBarPoint> bars;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: bars
          .map(
            (b) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      b.value.round().toString(),
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          height: ((b.value / maxValue) * 120).clamp(8, 120),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.8,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(b.label, style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
