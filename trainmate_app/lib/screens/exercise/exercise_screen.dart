import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../l10n/app_text.dart';
import '../../ml/exercise_rep_counter.dart';
import '../../ml/pose_feature_extractor.dart';
import '../../services/exercise_catalog_service.dart';
import '../../services/exercise_classifier_service.dart';
import '../../services/user_service.dart';
import '../../services/workout_service.dart';
import '../plans/plan_completion_screen.dart';
import '../../utils/camera_input_image.dart';
import '../../utils/workout_coach_hints.dart';

enum _ExercisePhase { setup, coaching, live }

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  PoseDetector? _poseDetector;
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  _ExercisePhase _phase = _ExercisePhase.setup;
  bool _optionsReady = false;
  bool _initializing = false;
  String? _cameraError;
  bool _busy = false;
  bool _useFrontCamera = false;
  bool _flipBusy = false;
  /// Compact stats chip (top-right); expand for full overlay text.
  bool _hudExpanded = false;
  int _frameTick = 0;

  final List<List<double>> _featureWindow = [];
  String _predictedLabel = '—';
  /// Starts false until [ExerciseClassifierService] loads; set true only if a model is available.
  bool _autoMode = false;
  List<String> _manualOptions = const ['push-up'];
  String _manualLabel = 'push-up';
  final RepCounterState _repState = RepCounterState();
  DateTime? _sessionStart;
  String? _statusMsg;
  String? _statusErr;
  final _weightCtrl = TextEditingController();
  Timer? _uiTicker;
  double? _profileWeightKg;
  String _equipment = 'bodyweight';
  int _sets = 3;
  bool _generateAiReport = true;

  String get _effectiveLabel => _autoMode ? _predictedLabel : _manualLabel;

  int get _displayReps {
    final l = _effectiveLabel;
    if (l == '—' || l.isEmpty) return 0;
    return totalRepsForLabel(_repState, l);
  }

  @override
  void initState() {
    super.initState();
    _loadClassifier();
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.stream,
        model: PoseDetectionModel.accurate,
      ),
    );
    _loadManualOptions();
    _loadProfileWeight();
  }

  Future<void> _loadClassifier() async {
    await ExerciseClassifierService.instance.load();
    if (!mounted) return;
    setState(() {
      _autoMode = ExerciseClassifierService.instance.isReady;
    });
  }

  Future<void> _loadProfileWeight() async {
    try {
      final me = await UserService().getMe();
      if (!mounted) return;
      setState(() => _profileWeightKg = me.profile?.weightKg);
    } catch (_) {}
  }

  void _startUiTicker() {
    _uiTicker?.cancel();
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  int get _sessionElapsedSec {
    final s = _sessionStart;
    if (s == null) return 0;
    return DateTime.now().difference(s).inSeconds;
  }

  String _formatDuration(int sec) {
    final m = sec ~/ 60;
    final r = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  double? get _parsedLoadKg {
    final t = _weightCtrl.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  double? _liveKcal() {
    final label = _effectiveLabel;
    if (label == '—' || label.isEmpty) return null;
    final load = _equipment == 'bodyweight' ? null : _parsedLoadKg;
    final reps = _displayReps;
    return estimateSessionKcal(
      exerciseLabel: label,
      userBodyWeightKg: _profileWeightKg,
      extraLoadKg: load,
      reps: reps,
      sets: _sets,
      durationSec: _sessionElapsedSec,
    );
  }

  Future<void> _loadManualOptions() async {
    try {
      final options = await ExerciseCatalogService.instance.getExercises();
      final sorted = options.toList()..sort();
      if (!mounted) return;
      if (sorted.isNotEmpty) {
        setState(() {
          _manualOptions = sorted;
          if (!_manualOptions.contains(_manualLabel)) {
            _manualLabel = _manualOptions.first;
          }
          _optionsReady = true;
        });
      } else {
        setState(() => _optionsReady = true);
      }
    } catch (_) {
      if (mounted) setState(() => _optionsReady = true);
    }
  }

  bool get _hasFrontAndBackCamera {
    if (_cameras.length < 2) return false;
    final hasFront = _cameras.any(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    final hasBack = _cameras.any(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    return hasFront && hasBack;
  }

  CameraDescription _pickLens(bool wantFront) {
    CameraDescription? front;
    CameraDescription? back;
    for (final c in _cameras) {
      if (c.lensDirection == CameraLensDirection.front) front = c;
      if (c.lensDirection == CameraLensDirection.back) back = c;
    }
    if (wantFront && front != null) return front;
    if (!wantFront && back != null) return back;
    return _cameras.first;
  }

  Future<void> _startPreviewForLens(bool useFront, {required bool startSessionClock}) async {
    final desc = _pickLens(useFront);
    final controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    await controller.startImageStream(_processCameraImage);
    if (!mounted) return;
    setState(() {
      _cameraController = controller;
      _useFrontCamera = useFront;
      _initializing = false;
      if (startSessionClock) _sessionStart = DateTime.now();
    });
  }

  Future<void> _openCameraForLive({required bool startSessionClock}) async {
    try {
      _cameras = await availableCameras();
      final t = mounted ? AppText.of(context) : null;
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _initializing = false;
            _cameraError = t?.tr('exercise.noCamera') ?? 'No camera found';
          });
        }
        return;
      }
      await _startPreviewForLens(_useFrontCamera, startSessionClock: startSessionClock);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _cameraError = e.toString();
        });
      }
    }
  }

  void _goToCoaching() {
    if (!_optionsReady) return;
    if (!_autoMode && (_manualLabel.trim().isEmpty || _manualOptions.isEmpty)) {
      final t = AppText.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.tr('exercise.selectValid'))),
      );
      return;
    }
    setState(() {
      _phase = _ExercisePhase.coaching;
      _statusErr = null;
      _statusMsg = null;
    });
  }

  void _backToSetupFromCoaching() {
    setState(() {
      _phase = _ExercisePhase.setup;
      _statusErr = null;
    });
  }

  Future<void> _beginLiveSession() async {
    if (!_optionsReady) return;
    setState(() {
      _phase = _ExercisePhase.live;
      _initializing = true;
      _cameraError = null;
    });
    _resetReps();
    _sessionStart = null;
    _featureWindow.clear();
    _frameTick = 0;
    _predictedLabel = '—';
    _stopCameraSync();
    _uiTicker?.cancel();
    _useFrontCamera = false;
    await _openCameraForLive(startSessionClock: true);
    if (!mounted) return;
    if (_cameraController != null && _cameraError == null) {
      _startUiTicker();
    }
  }

  Future<void> _returnToSetupAfterSession() async {
    _uiTicker?.cancel();
    _sessionStart = null;
    _stopCameraSync();
    if (!mounted) return;
    setState(() {
      _phase = _ExercisePhase.setup;
      _initializing = false;
      _cameraError = null;
      _statusMsg = null;
      _statusErr = null;
    });
  }

  String _coachingHint(AppText t) {
    if (_autoMode) {
      final p = _predictedLabel.trim();
      if (p.isEmpty || p == '—') {
        return t.tr('exercise.autoModeCoachingBlurb');
      }
      return liveFormHintForExercise(p, arabic: t.isArabic);
    }
    return liveFormHintForExercise(_manualLabel, arabic: t.isArabic);
  }

  Future<void> _flipCamera() async {
    final t = AppText.of(context);
    if (_flipBusy || !_hasFrontAndBackCamera) {
      if (mounted && !_hasFrontAndBackCamera && _cameras.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.tr('exercise.singleCamera'))),
        );
      }
      return;
    }
    _flipBusy = true;
    setState(() => _initializing = true);
    try {
      final old = _cameraController;
      if (old != null) {
        if (old.value.isStreamingImages) await old.stopImageStream();
        await old.dispose();
      }
      _cameraController = null;
      _featureWindow.clear();
      _frameTick = 0;
      _predictedLabel = '—';
      await _startPreviewForLens(!_useFrontCamera, startSessionClock: false);
      _startUiTicker();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _cameraError = e.toString();
        });
      }
    } finally {
      _flipBusy = false;
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_phase != _ExercisePhase.live ||
        _busy ||
        _cameraController == null ||
        _poseDetector == null) {
      return;
    }
    _frameTick++;
    if (_frameTick % 3 != 0) return;

    final controller = _cameraController!;
    final input = inputImageFromCameraImage(
      image,
      controller,
      controller.description,
    );
    if (input == null) return;

    _busy = true;
    try {
      final poses = await _poseDetector!.processImage(input);
      if (!mounted || poses.isEmpty) return;

      final pose = poses.first;
      final w = image.width.toDouble();
      final h = image.height.toDouble();

      final grid = LandmarkPixelGrid(w, h)..fromPose(pose);
      final vec36 = build36LandmarksFromPose(pose);
      if (vec36 == null) return;

      final feat = extractPoseFeatures(vec36);
      if (feat.every((e) => e == -1.0)) return;

      _featureWindow.add(feat);
      if (_featureWindow.length >= 30) {
        if (_autoMode && ExerciseClassifierService.instance.isReady) {
          final pred = await ExerciseClassifierService.instance.predictClass(
            List<List<double>>.from(_featureWindow),
          );
          if (mounted && pred != null) {
            _predictedLabel = pred;
            setState(() {});
          }
        }
        _featureWindow.clear();
      }

      final label = _effectiveLabel;
      if (label != '—' && label.isNotEmpty) {
        updateRepsForLabel(label, grid, _repState);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // drop frame
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveWorkout() async {
    if (_phase != _ExercisePhase.live) return;
    final label = _effectiveLabel;
    if (label == '—' || label.isEmpty) {
      final t = AppText.of(context);
      setState(() {
        _statusErr = t.tr('exercise.selectValid');
        _statusMsg = null;
      });
      return;
    }
    final reps = _displayReps;
    final dur = _sessionStart == null
        ? null
        : DateTime.now().difference(_sessionStart!).inSeconds;
    final loadKg = _equipment == 'bodyweight' ? null : _parsedLoadKg;
    final kcalEst = _liveKcal();
    setState(() {
      _statusErr = null;
      _statusMsg = null;
    });
    try {
      final saved = await WorkoutService().createWorkout(
        exerciseLabel: label,
        reps: reps,
        durationSec: dur,
        source: _autoMode ? 'auto_classify' : 'manual_exercise',
        weightKg: loadKg,
        equipment: _equipment,
        sets: _sets,
        estimatedKcal: kcalEst,
        generateAiReport: _generateAiReport,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      if (!mounted) return;
      final t = AppText.of(context);
      setState(() => _statusMsg = t.tr('exercise.workoutSaved'));
      final report = saved.sessionReport
          ?.replaceAll(RegExp(r'[#*•]+'), '')
          .replaceAll('\r', '')
          .trim();
      if (report != null && report.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.tr('exercise.reportTitle')),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(child: SelectableText(report)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(t.tr('exercise.close')),
              ),
            ],
          ),
        );
      }

      final me = await UserService().getMe();
      if (!mounted) return;
      final activePlan = me.activePlan;
      if (activePlan != null && activePlan.isPlanFinished) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PlanCompletionScreen(plan: activePlan),
          ),
        );
        return;
      }

      await _returnToSetupAfterSession();
    } catch (e) {
      if (mounted) {
        setState(() => _statusErr = e.toString());
      }
    }
  }

  void _resetReps() {
    setState(() {
      _repState.reset();
      _featureWindow.clear();
      _predictedLabel = '—';
    });
  }

  void _stopCameraSync() {
    final c = _cameraController;
    _cameraController = null;
    if (c != null) {
      if (c.value.isStreamingImages) {
        c.stopImageStream().then((_) => c.dispose());
      } else {
        c.dispose();
      }
    }
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    _weightCtrl.dispose();
    _stopCameraSync();
    _poseDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppText.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.tr('exercise.title')),
        leading: _phase == _ExercisePhase.coaching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _backToSetupFromCoaching,
              )
            : null,
        actions: [
          if (_phase == _ExercisePhase.live) ...[
            IconButton(
              onPressed: _initializing ||
                      _flipBusy ||
                      !_hasFrontAndBackCamera
                  ? null
                  : _flipCamera,
              icon: Icon(
                _useFrontCamera
                    ? Icons.camera_rear_rounded
                    : Icons.camera_front_rounded,
              ),
              tooltip: t.tr('exercise.flipCamera'),
            ),
            IconButton(
              onPressed: _initializing ? null : _resetReps,
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: t.tr('exercise.resetCounters'),
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final t = AppText.of(context);
    final theme = Theme.of(context);
    if (_phase == _ExercisePhase.setup) {
      if (!_optionsReady) {
        return Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        );
      }
      return _buildSetupBody(theme, t);
    }
    if (_phase == _ExercisePhase.coaching) {
      return _buildCoachingBody(theme, t);
    }
    return _buildLiveSessionBody(theme, t);
  }

  Widget _buildSetupBody(ThemeData theme, AppText t) {
    final cs = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.tr('exercise.setupIntro'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            _exerciseOptionsContent(theme, t),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _goToCoaching,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(t.tr('exercise.continueToFormTips')),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoachingBody(ThemeData theme, AppText t) {
    final cs = theme.colorScheme;
    final title = _autoMode
        ? t.tr('exercise.auto')
        : ExerciseCatalogService.instance.toDisplayName(_manualLabel);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.tr('exercise.formTipsTitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Card(
                    elevation: 2,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _coachingHint(t),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _beginLiveSession,
              icon: const Icon(Icons.videocam_rounded),
              label: Text(t.tr('exercise.readyOpenCamera')),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _backToSetupFromCoaching,
              child: Text(t.tr('exercise.backToOptions')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveSessionBody(ThemeData theme, AppText t) {
    if (_initializing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              t.tr('exercise.startingCamera'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  unawaited(_returnToSetupAfterSession());
                },
                child: Text(t.tr('exercise.backToOptions')),
              ),
            ],
          ),
        ),
      );
    }
    final c = _cameraController;
    if (c == null || !c.value.isInitialized) {
      return Center(child: Text(t.tr('exercise.cameraNotReady')));
    }

    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: CameraPreview(c)),
              Positioned(
                top: 8,
                right: 8,
                child: _buildWorkoutHud(theme, t),
              ),
            ],
          ),
        ),
        if (_statusErr != null || _statusMsg != null)
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.65,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                _statusErr ?? _statusMsg ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _statusErr != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.tertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        _buildBottomBar(theme, t),
      ],
    );
  }

  /// Compact stats (top-right). Tap to expand details; [expand_less] to collapse.
  Widget _buildWorkoutHud(ThemeData theme, AppText t) {
    final screenW = MediaQuery.sizeOf(context).width;
    final expandedW = math.min(300.0, screenW * 0.5);
    // Compact chip was fixed at 118px; Arabic hud hint + icon overflows (yellow/black stripes).
    final collapsedW = math.min(220.0, screenW - 24);
    return Material(
      color: const Color(0xB3000000),
      elevation: 8,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _hudExpanded ? expandedW : collapsedW,
        ),
        child: _hudExpanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _autoMode
                                ? '${t.tr('exercise.auto')} · $_predictedLabel'
                                : '${t.tr('exercise.manual')} · $_manualLabel',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () =>
                              setState(() => _hudExpanded = false),
                          icon: Icon(
                            Icons.expand_less_rounded,
                            color: Colors.white.withValues(alpha: 0.95),
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.tr(
                        'exercise.reps',
                        args: {'value': '$_displayReps'},
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t.tr(
                        'exercise.sessionTime',
                        args: {'value': _formatDuration(_sessionElapsedSec)},
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      t.tr(
                        'exercise.estimatedKcal',
                        args: {
                          'value': _liveKcal() != null
                              ? _liveKcal()!.toStringAsFixed(0)
                              : t.tr('exercise.kcalDash'),
                        },
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    if (_effectiveLabel != '—' &&
                        _effectiveLabel.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${t.tr('exercise.formCoach')}: ${liveFormHintForExercise(_effectiveLabel, arabic: t.isArabic)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      if (_repState.formFault != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.orangeAccent.shade200,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                formFaultMessage(
                                  _repState.formFault,
                                  arabic: t.isArabic,
                                ),
                                style: TextStyle(
                                  color: Colors.orangeAccent.shade100,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_repState.totalRepsTracked > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          t.tr(
                            'exercise.formQuality',
                            args: {
                              'value':
                                  '${(_repState.goodFormRatio * 100).round()}',
                            },
                          ),
                          style: TextStyle(
                            color: _repState.goodFormRatio >= 0.7
                                ? Colors.tealAccent.shade100
                                : Colors.orangeAccent.shade100,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                    if (!ExerciseClassifierService.instance.isReady) ...[
                      const SizedBox(height: 6),
                      Text(
                        t.tr('exercise.modelUnavailable'),
                        style: TextStyle(
                          color: Colors.orange.shade200,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (ExerciseClassifierService.instance.usesServer) ...[
                      const SizedBox(height: 6),
                      Text(
                        t.tr('exercise.autoServer'),
                        style: TextStyle(
                          color: Colors.tealAccent.shade100,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : InkWell(
                onTap: () => setState(() => _hudExpanded = true),
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_repState.formFault != null) ...[
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.orangeAccent.shade200,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '$_displayReps',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatDuration(_sessionElapsedSec),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.tr('exercise.hudHint'),
                              textAlign: TextAlign.end,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.expand_more_rounded,
                            color: Colors.white.withValues(alpha: 0.75),
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, AppText t) {
    final cs = theme.colorScheme;
    return Material(
      elevation: 12,
      shadowColor: Colors.black26,
      color: cs.surface,
      surfaceTintColor: cs.surfaceTint,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openExerciseOptionsSheet,
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(t.tr('exercise.optionsTitle')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saveWorkout,
                icon: const Icon(Icons.cloud_done_rounded),
                label: Text(t.tr('exercise.finishAndSave')),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openExerciseOptionsSheet() {
    final theme = Theme.of(context);
    final t = AppText.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _exerciseOptionsContent(theme, t),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Future.microtask(() => _saveWorkout());
                  },
                  icon: const Icon(Icons.cloud_upload_rounded),
                  label: Text(t.tr('exercise.saveToServer')),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                if (_statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _statusMsg!,
                      style: TextStyle(
                        color: theme.colorScheme.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_statusErr != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _statusErr!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _exerciseOptionsContent(ThemeData theme, AppText t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.tr('exercise.autoClassify'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Switch(
              value: _autoMode,
              onChanged: (v) => setState(() => _autoMode = v),
            ),
          ],
        ),
        if (!_autoMode)
          DropdownButtonFormField<String>(
            key: ValueKey(_manualLabel),
            // ignore: deprecated_member_use
            value: _manualLabel,
            decoration: InputDecoration(
              labelText: t.tr('exercise.exercise'),
            ),
            items: _manualOptions
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      ExerciseCatalogService.instance.toDisplayName(e),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) =>
                setState(() => _manualLabel = v ?? _manualOptions.first),
          ),
        if (!_autoMode) const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            t.tr('exercise.equipment'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: Text(t.tr('exercise.equipmentBodyweight')),
              selected: _equipment == 'bodyweight',
              onSelected: (v) {
                if (v) setState(() => _equipment = 'bodyweight');
              },
            ),
            FilterChip(
              label: Text(t.tr('exercise.equipmentBar')),
              selected: _equipment == 'bar',
              onSelected: (v) {
                if (v) setState(() => _equipment = 'bar');
              },
            ),
            FilterChip(
              label: Text(t.tr('exercise.equipmentDumbbell')),
              selected: _equipment == 'dumbbell',
              onSelected: (v) {
                if (v) setState(() => _equipment = 'dumbbell');
              },
            ),
            FilterChip(
              label: Text(t.tr('exercise.equipmentOther')),
              selected: _equipment == 'other',
              onSelected: (v) {
                if (v) setState(() => _equipment = 'other');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _weightCtrl,
          enabled: _equipment != 'bodyweight',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: t.tr('exercise.loadKg'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              t.tr('exercise.sets'),
              style: theme.textTheme.titleSmall,
            ),
            IconButton(
              onPressed: _sets > 1 ? () => setState(() => _sets--) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Text(
              '$_sets',
              style: theme.textTheme.titleMedium,
            ),
            IconButton(
              onPressed: _sets < 30 ? () => setState(() => _sets++) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            t.tr('exercise.aiReport'),
            style: theme.textTheme.bodyMedium,
          ),
          value: _generateAiReport,
          onChanged: (v) => setState(() => _generateAiReport = v),
        ),
      ],
    );
  }
}
