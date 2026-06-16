import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_text.dart';
import '../../models/workout_plan_model.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/plan_service.dart';
import '../../services/user_service.dart';
import '../progress/body_progress_screen.dart';
import '../plans/plan_form_screen.dart';

class PlanSettingsScreen extends StatefulWidget {
  const PlanSettingsScreen({super.key});

  @override
  State<PlanSettingsScreen> createState() => _PlanSettingsScreenState();
}

class _PlanSettingsScreenState extends State<PlanSettingsScreen> {
  final _planService = PlanService();
  final _user = UserService();
  final _picker = ImagePicker();
  int? _savingPhotoPlanId;
  List<WorkoutPlanModel> _plans = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await _planService.listPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _activate(WorkoutPlanModel plan) async {
    try {
      await _planService.activatePlan(plan.id);
      await _user.getMe();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete(WorkoutPlanModel plan) async {
    final t = AppText.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.tr('plans.deleteTitle')),
        content: Text(t.tr('plans.deleteConfirm', args: {'name': plan.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.tr('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _planService.deletePlan(plan.id);
      await _user.getMe();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _captureAfterAndAnalyze(WorkoutPlanModel plan) async {
    final before = plan.beforePhotoBase64;
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final afterB64 = base64Encode(bytes);

    setState(() => _savingPhotoPlanId = plan.id);
    try {
      await _planService.updatePlan(plan.id, afterPhotoBase64: afterB64);
      await _user.getMe();
      await _load();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BodyProgressScreen(
            planId: plan.id,
            category: plan.templateCategory ?? plan.name,
            beforePhotoBase64: before,
            afterPhotoBase64: afterB64,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _savingPhotoPlanId = null);
    }
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PlanFormScreen()),
    );
    if (changed == true) await _load();
  }

  Future<void> _openEdit(WorkoutPlanModel plan) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PlanFormScreen(existing: plan)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t.tr('settings.planSettings'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: Text(t.tr('plans.createPlan')),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  Text(t.tr('plans.listHint'), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  if (_plans.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text(t.tr('plans.empty'))),
                    ),
                  ..._plans.map((plan) => _planCard(plan, t, theme)),
                ],
              ),
            ),
    );
  }

  Widget _photoStatus(WorkoutPlanModel plan, AppText t, ThemeData theme) {
    final hasBefore = plan.beforePhotoBase64 != null;
    final hasAfter = plan.afterPhotoBase64 != null;

    final IconData icon;
    final Color color;
    final String text;
    if (hasBefore && hasAfter) {
      icon = Icons.check_circle_rounded;
      color = Colors.green.shade600;
      text = t.tr('progress.bothSaved');
    } else if (hasBefore) {
      icon = Icons.hourglass_bottom_rounded;
      color = Colors.orange.shade700;
      text = t.tr('progress.afterPending');
    } else {
      icon = Icons.photo_camera_outlined;
      color = theme.colorScheme.outline;
      text = t.tr('progress.beforeSaved');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
        if (hasBefore && !hasAfter) ...[
          const SizedBox(height: 4),
          Text(
            t.tr('progress.afterHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _planCard(WorkoutPlanModel plan, AppText t, ThemeData theme) {
    final exPreview = plan.exercises
        .take(3)
        .map(ExerciseCatalogService.instance.toDisplayName)
        .join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(plan.name, style: theme.textTheme.titleMedium),
                ),
                if (plan.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.tr('plans.active'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${plan.durationWeeks} ${t.tr('common.weeks')} · ${plan.exercises.length} ${t.tr('plans.exercises')}',
              style: theme.textTheme.bodySmall,
            ),
            if (exPreview.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(exPreview, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 8),
            _photoStatus(plan, t, theme),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!plan.isActive)
                  FilledButton.tonal(
                    onPressed: () => _activate(plan),
                    child: Text(t.tr('plans.activate')),
                  ),
                OutlinedButton(
                  onPressed: () => _openEdit(plan),
                  child: Text(t.tr('plans.edit')),
                ),
                if (plan.beforePhotoBase64 != null &&
                    plan.afterPhotoBase64 != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BodyProgressScreen(
                            planId: plan.id,
                            category: plan.templateCategory ?? plan.name,
                            beforePhotoBase64: plan.beforePhotoBase64,
                            afterPhotoBase64: plan.afterPhotoBase64,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: Text(t.tr('progress.analyze')),
                  )
                else if (plan.beforePhotoBase64 != null)
                  FilledButton.icon(
                    onPressed: _savingPhotoPlanId == plan.id
                        ? null
                        : () => _captureAfterAndAnalyze(plan),
                    icon: _savingPhotoPlanId == plan.id
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(
                      _savingPhotoPlanId == plan.id
                          ? t.tr('progress.savingPhoto')
                          : t.tr('progress.addAfterPhoto'),
                    ),
                  ),
                TextButton(
                  onPressed: () => _delete(plan),
                  child: Text(t.tr('common.delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
