import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_text.dart';
import '../../services/app_preferences_service.dart';
import '../../services/app_status_service.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  BackendHealth? _health;
  bool? _mlOnServer;
  bool _loadingDiag = true;

  @override
  void initState() {
    super.initState();
    _refreshDiagnostics();
  }

  Future<void> _refreshDiagnostics() async {
    setState(() => _loadingDiag = true);
    final h = await AppStatusService.instance.fetchBackendHealth();
    final m = await AppStatusService.instance.fetchMlServerAvailable();
    if (!mounted) return;
    setState(() {
      _health = h;
      _mlOnServer = m;
      _loadingDiag = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = AppPreferencesService.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, child) {
        final t = AppText.of(context);
        final baseUrl = AppConstants.compileTimeApiBaseUrl;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.tr('settings.appSettings')),
            actions: [
              IconButton(
                onPressed: _loadingDiag ? null : _refreshDiagnostics,
                icon: _loadingDiag
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: t.tr('settings.refreshDiag'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.tr('settings.backendDiagnostics'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        '${t.tr('settings.apiBaseUrl')}\n$baseUrl',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      if (_health == null)
                        Text(
                          t.tr('settings.backendUnreachable'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        )
                      else ...[
                        Text(
                          t.tr(
                            'settings.backendOk',
                            args: {'status': _health!.status},
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _health!.groqConfigured
                              ? t.tr('settings.groqOn')
                              : t.tr('settings.groqOff'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _health!.groqConfigured
                                    ? Theme.of(context).colorScheme.tertiary
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _mlOnServer == true
                              ? t.tr('settings.mlServerOn')
                              : t.tr('settings.mlServerOff'),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                height: 1.35,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(t.tr('settings.theme')),
              const SizedBox(height: 8),
              SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(t.tr('settings.light')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(t.tr('settings.dark')),
                  ),
                ],
                selected: {prefs.themeMode},
                onSelectionChanged: (v) => prefs.setThemeMode(v.first),
              ),
              const SizedBox(height: 16),
              Text(t.tr('settings.language')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'en', label: Text('English')),
                  ButtonSegment(value: 'ar', label: Text('العربية')),
                ],
                selected: {prefs.locale.languageCode},
                onSelectionChanged: (v) =>
                    prefs.setLocale(Locale(v.first)),
              ),
              const SizedBox(height: 24),
              Text(t.tr('settings.workoutPreferences')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kg', label: Text('KG')),
                  ButtonSegment(value: 'lb', label: Text('LB')),
                ],
                selected: {prefs.weightUnit},
                onSelectionChanged: (v) => prefs.setWeightUnit(v.first),
              ),
              const SizedBox(height: 12),
              Text(
                t.tr(
                  'settings.restTimer',
                  args: {'seconds': '${prefs.restTimerSeconds}'},
                ),
              ),
              Slider(
                value: prefs.restTimerSeconds.toDouble(),
                min: 30,
                max: 300,
                divisions: 9,
                label: '${prefs.restTimerSeconds}s',
                onChanged: (value) =>
                    prefs.setRestTimerSeconds(value.round()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.aiExerciseOnlyMode,
                title: Text(t.tr('settings.aiExercisesOnly')),
                subtitle: Text(t.tr('settings.aiExercisesOnlySubtitle')),
                onChanged: (v) => prefs.setAiExerciseOnlyMode(v),
              ),
              const SizedBox(height: 12),
              Text(t.tr('settings.bodyGoal')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: prefs.bodyGoal,
                decoration: InputDecoration(
                  labelText: t.tr('settings.bodyGoal'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'balanced_fitness',
                    child: Text(t.tr('goal.balanced_fitness')),
                  ),
                  DropdownMenuItem(
                    value: 'fat_loss',
                    child: Text(t.tr('goal.fat_loss')),
                  ),
                  DropdownMenuItem(
                    value: 'muscle_building',
                    child: Text(t.tr('goal.muscle_building')),
                  ),
                  DropdownMenuItem(
                    value: 'strength_performance',
                    child: Text(t.tr('goal.strength_performance')),
                  ),
                  DropdownMenuItem(
                    value: 'body_recomposition',
                    child: Text(t.tr('goal.body_recomposition')),
                  ),
                ],
                onChanged: (v) => prefs.setBodyGoal(v ?? prefs.bodyGoal),
              ),
              const SizedBox(height: 10),
              Text(
                t.tr(
                  'settings.trainingDaysPerWeek',
                  args: {'value': '${prefs.trainingDaysPerWeek}'},
                ),
              ),
              Slider(
                value: prefs.trainingDaysPerWeek.toDouble(),
                min: 2,
                max: 6,
                divisions: 4,
                label: '${prefs.trainingDaysPerWeek}',
                onChanged: (value) =>
                    prefs.setTrainingDaysPerWeek(value.round()),
              ),
            ],
          ),
        );
      },
    );
  }
}
