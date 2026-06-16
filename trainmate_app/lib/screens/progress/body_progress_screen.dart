import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_text.dart';
import '../../models/body_progress_result.dart';
import '../../services/app_preferences_service.dart';
import '../../services/body_progress_service.dart';
import '../../services/plan_service.dart';

class BodyProgressScreen extends StatefulWidget {
  const BodyProgressScreen({
    super.key,
    required this.category,
    this.planId,
    this.beforePhotoBase64,
    this.afterPhotoBase64,
    this.initialResult,
  });

  final String category;
  final int? planId;
  final String? beforePhotoBase64;
  final String? afterPhotoBase64;
  final BodyProgressResult? initialResult;

  @override
  State<BodyProgressScreen> createState() => _BodyProgressScreenState();
}

class _BodyProgressScreenState extends State<BodyProgressScreen> {
  final _service = BodyProgressService();
  final _planService = PlanService();
  BodyProgressResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null &&
        widget.beforePhotoBase64 != null &&
        widget.afterPhotoBase64 != null) {
      _analyze();
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      BodyProgressResult r;
      if (widget.planId != null) {
        final lang = AppPreferencesService.instance.locale.languageCode;
        final raw = await _planService.analyzePlanBody(
          widget.planId!,
          languageCode: lang,
        );
        r = BodyProgressResult.fromJson(raw);
      } else {
        r = await _service.analyze(
          beforePhotoBase64: widget.beforePhotoBase64,
          afterPhotoBase64: widget.afterPhotoBase64,
          category: widget.category,
        );
      }
      if (!mounted) return;
      setState(() => _result = r);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
            height: 180,
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
      height: 180,
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
    final r = _result;

    return Scaffold(
      appBar: AppBar(title: Text(t.tr('progress.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _photoTile(t.tr('progress.before'), widget.beforePhotoBase64, theme)),
              const SizedBox(width: 12),
              Expanded(child: _photoTile(t.tr('progress.after'), widget.afterPhotoBase64, theme)),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _analyze, child: Text(t.tr('progress.retry'))),
              ],
            )
          else if (r != null) ...[
            _scoreCard(r, t, theme),
            const SizedBox(height: 16),
            Text(t.tr('progress.regionBreakdown'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...r.regions.map((region) => _regionCard(region, t, theme)),
            if (r.narrative != null && r.narrative!.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(t.tr('progress.aiCoach'), style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(r.narrative!),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _analyze,
              icon: const Icon(Icons.refresh),
              label: Text(t.tr('progress.reanalyze')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scoreCard(BodyProgressResult r, AppText t, ThemeData theme) {
    final alignedColor = r.planAligned ? Colors.green.shade600 : Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.tr('progress.category')}: ${r.category}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 12),
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
                r.noMeasurableChange
                    ? t.tr('progress.measurableChange')
                    : t.tr('progress.planAlignment'),
                r.noMeasurableChange
                    ? '0%'
                    : '${r.planAlignmentPercent.toStringAsFixed(0)}%',
                r.noMeasurableChange ? Colors.orange.shade800 : alignedColor,
                theme,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                r.planAligned ? Icons.check_circle : Icons.info_outline,
                color: alignedColor,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.noMeasurableChange
                      ? t.tr('progress.noChangeDetected')
                      : (r.planAligned
                            ? t.tr('progress.planAlignedYes')
                            : t.tr('progress.planAlignedNo')),
                  style: theme.textTheme.bodyMedium?.copyWith(color: alignedColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(r.summary, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, Color color, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.85),
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
                Expanded(
                  child: Text(region.label, style: theme.textTheme.titleSmall),
                ),
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
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${t.tr('progress.change')}: ${region.changePercent >= 0 ? '+' : ''}${region.changePercent.toStringAsFixed(1)}%',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: 12),
                Text(
                  '${t.tr('progress.score')}: ${region.score.toStringAsFixed(0)}/100',
                  style: theme.textTheme.bodySmall,
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
