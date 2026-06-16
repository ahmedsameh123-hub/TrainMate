import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'api_service.dart';

/// 30 frames x 22 features window -> (TFLite on-device or Keras on server).
enum ExerciseModelBackend { none, tflite, server }

class ExerciseClassifierService {
  ExerciseClassifierService._();
  static final ExerciseClassifierService instance =
      ExerciseClassifierService._();

  ExerciseModelBackend _backend = ExerciseModelBackend.none;
  Interpreter? _interpreter;
  List<double>? _mean;
  List<double>? _scale;
  List<String>? _classes;
  int _window = 30;
  int _nPerFrame = 22;

  bool get isReady => _backend != ExerciseModelBackend.none;
  bool get isOnDevice => _backend == ExerciseModelBackend.tflite;
  bool get usesServer => _backend == ExerciseModelBackend.server;

  Future<bool> _serverMlAvailable() async {
    try {
      final r = await ApiService.get('/api/ml/status', auth: false);
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return j['available'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _closeInterpreter() async {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Loads TFLite from assets; if it fails, checks for Keras weights on the server.
  Future<bool> load() async {
    _backend = ExerciseModelBackend.none;
    _mean = null;
    _scale = null;
    _classes = null;
    await _closeInterpreter();

    try {
      final raw = await rootBundle.loadString(
        'assets/models/scaler_params.json',
      );
      final meta = jsonDecode(raw) as Map<String, dynamic>;
      _window = (meta['window_size'] as num?)?.toInt() ?? 30;
      _nPerFrame = (meta['n_features_per_frame'] as num?)?.toInt() ?? 22;
      _mean = (meta['mean'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
      _scale = (meta['scale'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();

      final clsRaw = await rootBundle.loadString('assets/models/classes.json');
      _classes = (jsonDecode(clsRaw) as List<dynamic>)
          .map((e) => e.toString())
          .toList();

      final expected = _window * _nPerFrame;
      if (_mean!.length != expected || _scale!.length != expected) {
        debugPrint(
          'exercise_classifier: scaler length ${_mean!.length} != expected $expected',
        );
        _mean = null;
        _scale = null;
        _classes = null;
      } else {
        _interpreter = await Interpreter.fromAsset(
          'assets/models/exercise_classifier.tflite',
        );
        _interpreter!.allocateTensors();
        _backend = ExerciseModelBackend.tflite;
        return true;
      }
    } catch (e, st) {
      debugPrint('exercise_classifier on-device load failed: $e\n$st');
      await _closeInterpreter();
      _mean = null;
      _scale = null;
      _classes = null;
    }

    if (await _serverMlAvailable()) {
      _backend = ExerciseModelBackend.server;
      return true;
    }

    return false;
  }

  Future<void> dispose() async {
    await _closeInterpreter();
    _mean = null;
    _scale = null;
    _classes = null;
    _backend = ExerciseModelBackend.none;
  }

  List<double> _applyScaler(List<double> flat) {
    final m = _mean!;
    final s = _scale!;
    return List<double>.generate(flat.length, (i) {
      final den = s[i];
      if (den == 0) return 0;
      return (flat[i] - m[i]) / den;
    });
  }

  Future<String?> _predictViaServer(List<List<double>> window30x22) async {
    final r = await ApiService.post(
      '/api/ml/classify',
      body: {'window': window30x22},
      auth: true,
    );
    if (r.statusCode != 200) {
      debugPrint('exercise_classifier server: ${r.statusCode} ${r.body}');
      return null;
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return j['label'] as String?;
  }

  Future<String?> predictClass(List<List<double>> window30x22) async {
    if (!isReady || window30x22.length != _window) return null;
    for (final row in window30x22) {
      if (row.length != _nPerFrame) return null;
    }

    if (_backend == ExerciseModelBackend.server) {
      return _predictViaServer(window30x22);
    }

    if (_backend != ExerciseModelBackend.tflite ||
        _interpreter == null ||
        _mean == null ||
        _scale == null ||
        _classes == null) {
      return null;
    }

    final flat = <double>[];
    for (final row in window30x22) {
      flat.addAll(row);
    }
    final scaled = _applyScaler(flat);

    final input = [
      List.generate(
        _window,
        (t) => List.generate(_nPerFrame, (f) => scaled[t * _nPerFrame + f]),
      ),
    ];

    final outShape = _interpreter!.getOutputTensor(0).shape;
    final out = List.generate(
      outShape[0],
      (_) => List<double>.filled(outShape[1], 0),
    );

    _interpreter!.run(input, out);

    final logits = out[0];
    var best = 0;
    for (var i = 1; i < logits.length; i++) {
      if (logits[i] > logits[best]) best = i;
    }
    if (best >= _classes!.length) return null;
    return _classes![best];
  }
}
