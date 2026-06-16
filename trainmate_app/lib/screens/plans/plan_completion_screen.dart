import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_text.dart';
import '../../models/body_progress_result.dart';
import '../../models/plan_completion_data.dart';
import '../../models/workout_plan_model.dart';
import '../../services/app_sync_signal.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/plan_service.dart';
import '../../services/user_service.dart';
import 'plan_form_screen.dart';

class PlanCompletionScreen extends StatefulWidget {
  const PlanCompletionScreen({
    super.key,
    required this.plan,
    this.initialData,
    this.readOnly = false,
  });

  final WorkoutPlanModel plan;
  final PlanCompletionData? initialData;
  final bool readOnly;

  @override
  State<PlanCompletionScreen> createState() => _PlanCompletionScreenState();
}

class _PlanCompletionScreenState extends State<PlanCompletionScreen> {
  final _planService = PlanService();
  final _user = UserService();
  final _picker = ImagePicker();

  PlanCompletionData? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
  }

  Future<void> _captureAndComplete() async {
    final lang = Localizations.localeOf(context).languageCode;
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (file == null) return;
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bytes = await file.readAsBytes();
      final afterB64 = base64Encode(bytes);
      final result = await _planService.completePlan(
        widget.plan.id,
        afterPhotoBase64: afterB64,
        languageCode: lang,
      );
      await _user.getMe();
      AppSyncSignal.notifyRefresh();
      if (!mounted) return;
      setState(() => _data = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startNewPlan() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PlanFormScreen()),
    );
    if (created == true && mounted) {
      await _user.getMe();
      AppSyncSignal.notifyRefresh();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    }
  }

  Color _statusColor(String status, ThemeData theme) {
    switch (status) {
      case 'improved':
        return Colors.green.shade600;
      case 'regressed':
        return theme.colorScheme.error;
      case 'maintained':
        return Colors.orange.shade700;
      default:
        return theme.colorScheme.outline;
    }
  }

  String _statusLabel(String status, AppText t) {
    switch (status) {
      case 'improved':
        return t.tr('progress.statusImproved');
      case 'regressed':
        return t.tr('progress.statusRegressed');
      case 'maintained':
        return t.tr('progress.statusMaintained');
      default:
        return t.tr('progress.statusUnclear');
    }
  }

  Widget _photoTile(String label, String? b64, ThemeData theme) {
    Widget child;
    if (b64 != null && b64.isNotEmpty) {
      try {
        child = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            base64Decode(b64),
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        child = _photoPlaceholder(theme);
      }
    } else {
      child = _photoPlaceholder(theme);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _photoPlaceholder(ThemeData theme) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.person_outline, size: 48, color: theme.colorScheme.outline),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    final data = _data;
    final plan = data?.plan ?? widget.plan;
    final analysis = data?.analysis;
    final stats = data?.stats;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.tr('planComplete.title')),
        automaticallyImplyLeading: !widget.readOnly,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (data == null && !widget.readOnly) ...[
            Icon(Icons.emoji_events_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              t.tr('planComplete.congrats'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            if (_loading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(t.tr('planComplete.analyzing')),
                ],
              )
            else ...[
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _captureAndComplete,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(t.tr('planComplete.addAfterPhoto')),
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              ),
            ],
          ] else if (data != null) ...[
            Row(
              children: [
                Expanded(
                  child: _photoTile(
                    t.tr('progress.before'),
                    plan.beforePhotoBase64,
                    theme,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _photoTile(
                    t.tr('progress.after'),
                    plan.afterPhotoBase64,
                    theme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _percentRow(plan, t, theme),
            if (stats != null) ...[
              const SizedBox(height: 16),
              _statsCard(stats, t, theme),
            ],
            if (analysis != null) ...[
              const SizedBox(height: 16),
              _analysisCard(analysis, t, theme),
            ],
            if (!widget.readOnly) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _startNewPlan,
                icon: const Icon(Icons.add_circle_outline),
                label: Text(t.tr('planComplete.startNewPlan')),
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _percentRow(WorkoutPlanModel plan, AppText t, ThemeData theme) {
    return Row(
      children: [
        if (plan.completionPercent != null)
          Expanded(
            child: _metricChip(
              t.tr('planComplete.completionRate'),
              '${plan.completionPercent!.toStringAsFixed(0)}%',
              theme.colorScheme.primary,
              theme,
            ),
          ),
        if (plan.completionPercent != null && plan.aiOverallScore != null)
          const SizedBox(width: 10),
        if (plan.aiOverallScore != null)
          Expanded(
            child: _metricChip(
              t.tr('planComplete.improvementRate'),
              '${plan.aiOverallScore!.toStringAsFixed(0)}/100',
              Colors.green.shade600,
              theme,
            ),
          ),
      ],
    );
  }

  Widget _metricChip(String label, String value, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsCard(PlanCompletionStats stats, AppText t, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.tr('planComplete.workoutStats'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _statItem(t.tr('planComplete.totalSessions'), '${stats.totalSessions}', theme),
                _statItem(t.tr('planComplete.totalReps'), '${stats.totalReps}', theme),
                if (stats.totalKcal != null)
                  _statItem(
                    t.tr('planComplete.totalKcal'),
                    stats.totalKcal!.toStringAsFixed(0),
                    theme,
                  ),
              ],
            ),
            if (stats.byExercise.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.tr('planComplete.byExercise'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...stats.byExercise.map(
                (ex) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ExerciseCatalogService.instance.toDisplayName(ex.exercise)),
                  subtitle: Text(
                    '${ex.sessions} ${t.tr('plans.exercises')} · ${ex.totalReps} reps'
                    '${ex.totalKcal != null ? ' · ${ex.totalKcal!.toStringAsFixed(0)} kcal' : ''}',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _analysisCard(BodyProgressResult r, AppText t, ThemeData theme) {
    final alignedColor = r.planAligned ? Colors.green.shade600 : Colors.orange.shade800;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.tr('progress.title'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _metricChip(
                  t.tr('progress.overallScore'),
                  '${r.overallScore.toStringAsFixed(0)}/100',
                  theme.colorScheme.primary,
                  theme,
                ),
                const SizedBox(width: 10),
                _metricChip(
                  t.tr('progress.planAlignment'),
                  '${r.planAlignmentPercent.toStringAsFixed(0)}%',
                  alignedColor,
                  theme,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(r.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(t.tr('progress.regionBreakdown'), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...r.regions.map((region) => _regionCard(region, t, theme)),
            if (r.narrative != null && r.narrative!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.tr('progress.aiCoach'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(r.narrative!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _regionCard(BodyRegionResult region, AppText t, ThemeData theme) {
    final color = _statusColor(region.status, theme);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(region.label, style: theme.textTheme.titleSmall)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(region.status, t),
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(region.detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
