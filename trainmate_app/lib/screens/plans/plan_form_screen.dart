import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/category_info.dart';
import '../../core/plan_templates.dart';
import '../../l10n/app_text.dart';
import '../../models/workout_plan_model.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/plan_service.dart';
import '../../services/user_service.dart';

/// Create or edit a workout plan (template pick or fully custom).
class PlanFormScreen extends StatefulWidget {
  const PlanFormScreen({
    super.key,
    this.onboardingMode = false,
    this.existing,
  });

  final bool onboardingMode;
  final WorkoutPlanModel? existing;

  @override
  State<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends State<PlanFormScreen>
    with SingleTickerProviderStateMixin {
  final _planService = PlanService();
  final _user = UserService();
  final _picker = ImagePicker();
  final _nameCtrl = TextEditingController();
  late TabController _tabs;

  bool _customMode = false;
  String _template = PlanTemplates.builtIn.first;
  int _durationWeeks = 8;
  String? _beforePhoto;
  String? _afterPhoto;
  List<String> _catalog = const [];
  final Set<String> _selectedExercises = {};
  bool _loading = false;
  bool _boot = true;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() => _customMode = _tabs.index == 1);
      }
    });
    _loadCatalog();
    if (widget.existing != null) _applyExisting(widget.existing!);
  }

  void _applyExisting(WorkoutPlanModel p) {
    _nameCtrl.text = p.name;
    _durationWeeks = p.durationWeeks;
    _beforePhoto = p.beforePhotoBase64;
    _afterPhoto = p.afterPhotoBase64;
    _selectedExercises
      ..clear()
      ..addAll(p.exercises);
    if (p.isCustom) {
      _customMode = true;
      _tabs.index = 1;
    } else {
      _template = p.templateCategory ?? p.name;
      if (!PlanTemplates.builtIn.contains(_template)) {
        _template = PlanTemplates.builtIn.first;
      }
    }
  }

  Future<void> _loadCatalog() async {
    List<String> list;
    try {
      list = await ExerciseCatalogService.instance.getExercises();
    } catch (_) {
      list = List<String>.from(PlanTemplates.supportedExercises)..sort();
    }
    if (!mounted) return;
    setState(() {
      _catalog = list;
      _boot = false;
      // Keep only exercises that actually exist in the app catalog.
      _selectedExercises.removeWhere((ex) => !list.contains(ex));
      if (_selectedExercises.isEmpty && !_isEdit) {
        _selectedExercises
            .addAll(PlanTemplates.exercisesFor(_template).where(list.contains));
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _applyTemplateExercises() {
    final available = _catalog.isEmpty
        ? PlanTemplates.supportedExercises
        : _catalog;
    _selectedExercises
      ..clear()
      ..addAll(PlanTemplates.exercisesFor(_template).where(available.contains));
  }

  Future<void> _pickPhoto({required bool after}) async {
    final source = widget.onboardingMode && !after
        ? ImageSource.camera
        : ImageSource.gallery;
    final file = await _picker.pickImage(source: source, imageQuality: 75);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (after) {
        _afterPhoto = base64Encode(bytes);
      } else {
        _beforePhoto = base64Encode(bytes);
      }
    });
  }

  Future<void> _save() async {
    final t = AppText.of(context);
    final name = _customMode
        ? _nameCtrl.text.trim()
        : t.categoryLabel(_template);

    if (_customMode && name.length < 2) {
      setState(() => _error = t.tr('plans.nameRequired'));
      return;
    }
    if (_selectedExercises.isEmpty) {
      setState(() => _error = t.tr('plans.exercisesRequired'));
      return;
    }
    if (widget.onboardingMode &&
        (_beforePhoto == null || _beforePhoto!.isEmpty)) {
      setState(() => _error = t.tr('onboarding.needPhoto'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        await _planService.updatePlan(
          widget.existing!.id,
          name: name,
          exercises: _selectedExercises.toList(),
          durationWeeks: _durationWeeks,
          beforePhotoBase64: _beforePhoto,
          afterPhotoBase64: _afterPhoto,
          onboardingCompleted: widget.onboardingMode ? true : null,
        );
      } else {
        final model = WorkoutPlanModel(
          id: 0,
          name: name,
          planKind: _customMode ? 'custom' : 'template',
          templateCategory: _customMode ? 'Muscle Gain' : _template,
          exercises: _selectedExercises.toList(),
          durationWeeks: _durationWeeks,
          beforePhotoBase64: _beforePhoto,
          afterPhotoBase64: _afterPhoto,
          isActive: true,
        );
        await _planService.createPlan(
          model,
          activate: true,
          onboardingCompleted: widget.onboardingMode ? true : null,
        );
      }

      await _user.getMe();
      if (!mounted) return;

      if (widget.onboardingMode) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    final theme = Theme.of(context);

    if (_boot) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.onboardingMode
                ? t.tr('onboarding.step2Title')
                : (_isEdit ? t.tr('plans.editPlan') : t.tr('plans.createPlan')),
          ),
        ),
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    Uint8List? beforePreview;
    if (_beforePhoto != null && _beforePhoto!.isNotEmpty) {
      beforePreview = base64Decode(_beforePhoto!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.onboardingMode
              ? t.tr('onboarding.step2Title')
              : (_isEdit ? t.tr('plans.editPlan') : t.tr('plans.createPlan')),
        ),
        bottom: _isEdit
            ? null
            : TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: t.tr('plans.readyPlans')),
                  Tab(text: t.tr('plans.customPlan')),
                ],
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.onboardingMode)
            Text(
              t.tr('onboarding.step2Desc'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (widget.onboardingMode) const SizedBox(height: 12),
          if (!_customMode && !_isEdit) ...[
            ...PlanTemplates.builtIn.map((cat) {
              final info = getCategoryInfo(cat, t);
              final selected = _template == cat;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: selected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                    : null,
                child: ListTile(
                  title: Text(t.categoryLabel(cat)),
                  subtitle: Text(info.focus, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: selected ? const Icon(Icons.check_circle) : null,
                  onTap: () => setState(() {
                    _template = cat;
                    _applyTemplateExercises();
                  }),
                ),
              );
            }),
          ],
          if (_customMode || _isEdit) ...[
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: t.tr('plans.planName'),
                hintText: t.tr('plans.planNameHint'),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text('${t.tr('settings.duration')}: $_durationWeeks ${t.tr('common.weeks')}'),
          Slider(
            value: _durationWeeks.toDouble(),
            min: 4,
            max: 12,
            divisions: 8,
            label: '$_durationWeeks',
            onChanged: (v) => setState(() => _durationWeeks = v.round()),
          ),
          Text(t.tr('plans.pickExercises'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _catalog.map((ex) {
              final picked = _selectedExercises.contains(ex);
              return FilterChip(
                label: Text(ExerciseCatalogService.instance.toDisplayName(ex)),
                selected: picked,
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedExercises.add(ex);
                    } else {
                      _selectedExercises.remove(ex);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _pickPhoto(after: false),
            icon: const Icon(Icons.photo_camera_back_outlined),
            label: Text(
              _beforePhoto == null
                  ? t.tr('settings.uploadBeforePhoto')
                  : t.tr('settings.changeBeforePhoto'),
            ),
          ),
          if (beforePreview != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(beforePreview, height: 160, fit: BoxFit.cover),
            ),
          ],
          if (!widget.onboardingMode) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : () => _pickPhoto(after: true),
              icon: const Icon(Icons.photo_camera_front_outlined),
              label: Text(
                _afterPhoto == null
                    ? t.tr('settings.uploadAfterPhoto')
                    : t.tr('settings.changeAfterPhoto'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              _loading
                  ? t.tr('common.saving')
                  : (widget.onboardingMode
                      ? t.tr('onboarding.completeSetup')
                      : t.tr('plans.savePlan')),
            ),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          ),
        ],
      ),
    );
  }
}
