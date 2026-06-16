import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Same 12-point order as `relevant_landmarks_indices` in `ai/ExerciseAiTrainer.py`.
const kRelevantMpIndices = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];

/// x,y,z for each of the 12 joints → length 36.
List<double>? build36LandmarksFromPose(Pose pose) {
  final out = <double>[];
  for (final idx in kRelevantMpIndices) {
    final t = PoseLandmarkType.values[idx];
    final lm = pose.landmarks[t];
    if (lm == null) return null;
    out.addAll([lm.x, lm.y, lm.z]);
  }
  return out;
}

/// Mirrors [ExerciseAiTrainer.extract_features] in `ai/ExerciseAiTrainer.py`.
List<double> extractPoseFeatures(List<double> landmarks) {
  if (landmarks.length != 36) {
    return List.filled(22, -1.0);
  }

  List<double> p(int start) => landmarks.sublist(start, start + 3);

  double angle2D(List<double> a, List<double> b, List<double> c) {
    var radians =
        math.atan2(c[1] - b[1], c[0] - b[0]) -
        math.atan2(a[1] - b[1], a[0] - b[0]);
    var angle = radians * 180.0 / math.pi;
    angle = angle.abs();
    if (angle > 180.0) angle = 360 - angle;
    return angle;
  }

  double dist2(List<double> a, List<double> b) {
    final dx = a[0] - b[0];
    final dy = a[1] - b[1];
    return math.sqrt(dx * dx + dy * dy);
  }

  double yDist(List<double> a, List<double> b) => (a[1] - b[1]).abs();

  final features = <double>[];
  features.add(angle2D(p(0), p(6), p(12)));
  features.add(angle2D(p(3), p(9), p(15)));
  features.add(angle2D(p(18), p(24), p(30)));
  features.add(angle2D(p(21), p(27), p(33)));
  features.add(angle2D(p(0), p(18), p(24)));
  features.add(angle2D(p(3), p(21), p(27)));
  features.add(angle2D(p(18), p(0), p(6)));
  features.add(angle2D(p(21), p(3), p(9)));

  final distances = <double>[
    dist2(p(0), p(3)),
    dist2(p(18), p(21)),
    dist2(p(18), p(24)),
    dist2(p(21), p(27)),
    dist2(p(0), p(18)),
    dist2(p(3), p(21)),
    dist2(p(6), p(24)),
    dist2(p(9), p(27)),
    dist2(p(12), p(0)),
    dist2(p(15), p(3)),
    dist2(p(12), p(18)),
    dist2(p(15), p(21)),
  ];

  final yDistances = <double>[yDist(p(6), p(0)), yDist(p(9), p(3))];

  var norm = -1.0;
  for (final d in [
    dist2(p(0), p(18)),
    dist2(p(3), p(21)),
    dist2(p(18), p(24)),
    dist2(p(21), p(27)),
  ]) {
    if (d > 0) {
      norm = d;
      break;
    }
  }
  if (norm < 0) norm = 0.5;

  features.addAll(distances.map((d) => d / norm));
  features.addAll(yDistances.map((d) => d / norm));

  return features;
}
