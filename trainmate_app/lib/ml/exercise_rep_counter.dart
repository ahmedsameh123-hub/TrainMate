import 'dart:math' as math;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pixel coordinates for MediaPipe indices 0..32 (same as [PoseLandmarkType.values] order).
class LandmarkPixelGrid {
  LandmarkPixelGrid(this.width, this.height);

  final double width;
  final double height;
  final List<List<double>?> pts = List.filled(33, null);
  final List<double> likelihood = List.filled(33, 0);

  void fromPose(Pose pose) {
    for (var i = 0; i < 33; i++) {
      final t = PoseLandmarkType.values[i];
      final lm = pose.landmarks[t];
      if (lm != null) {
        // ML Kit already returns landmark coordinates in image pixels.
        pts[i] = [lm.x, lm.y];
        likelihood[i] = lm.likelihood;
      } else {
        pts[i] = null;
        likelihood[i] = 0;
      }
    }
  }

  /// Raw 0..360 angle at vertex [p2] (kept for backward compatibility).
  double findAngle(int p1, int p2, int p3) {
    final a = pts[p1];
    final b = pts[p2];
    final c = pts[p3];
    if (a == null || b == null || c == null) return -1;
    var angle =
        (math.atan2(c[1] - b[1], c[0] - b[0]) -
            math.atan2(a[1] - b[1], a[0] - b[0])) *
        180 /
        math.pi;
    if (angle < 0) angle += 360;
    return angle;
  }

  /// Interior angle (0..180) at vertex [p2]. Returns -1 if any point is missing.
  double interiorAngle(int p1, int p2, int p3) {
    final raw = findAngle(p1, p2, p3);
    if (raw < 0) return -1;
    return raw > 180 ? 360 - raw : raw;
  }

  /// Best-available interior angle for a left/right joint pair (averages the
  /// sides that are confidently visible). Returns -1 when neither side is usable.
  double bilateralAngle(
    int l1,
    int l2,
    int l3,
    int r1,
    int r2,
    int r3, {
    double minVis = 0.5,
  }) {
    final double left =
        _visible(l1, minVis) && _visible(l2, minVis) && _visible(l3, minVis)
            ? interiorAngle(l1, l2, l3)
            : -1.0;
    final double right =
        _visible(r1, minVis) && _visible(r2, minVis) && _visible(r3, minVis)
            ? interiorAngle(r1, r2, r3)
            : -1.0;
    if (left >= 0 && right >= 0) return (left + right) / 2;
    if (left >= 0) return left;
    if (right >= 0) return right;
    return -1;
  }

  bool _visible(int i, double minVis) =>
      pts[i] != null && likelihood[i] >= minVis;

  bool handsJoined({double threshold = 30}) {
    final lw = pts[15];
    final rw = pts[16];
    if (lw == null || rw == null) return false;
    final d = math.sqrt(
      math.pow(lw[0] - rw[0], 2) + math.pow(lw[1] - rw[1], 2),
    );
    return d < threshold;
  }

  /// Vertical-axis angle (0 = perfectly vertical) of segment [top]→[bottom].
  double tiltFromVertical(int top, int bottom) {
    final a = pts[top];
    final b = pts[bottom];
    if (a == null || b == null) return -1;
    final dx = (b[0] - a[0]).abs();
    final dy = (b[1] - a[1]).abs();
    if (dx == 0 && dy == 0) return -1;
    return math.atan2(dx, dy) * 180 / math.pi;
  }
}

/// Stable, language-agnostic form-fault codes surfaced to the UI.
class FormFault {
  static const partialReps = 'partialReps';
  static const hipSag = 'hipSag';
  static const hipPike = 'hipPike';
  static const shallowSquat = 'shallowSquat';
  static const torsoLean = 'torsoLean';
  static const swinging = 'swinging';
  static const elbowFlare = 'elbowFlare';
  static const lockout = 'lockout';
  static const backArch = 'backArch';
}

/// Mutable stages/counters plus live form-quality tracking.
class RepCounterState {
  String? stagePush;
  String? stageSquat;
  String? stageRightCurl;
  String? stageLeftCurl;
  String? stagePress;
  int pushUps = 0;
  int squats = 0;
  int bicepCurls = 0;
  int shoulderPresses = 0;

  /// Extreme joint angle reached within the current (in-progress) rep, used to
  /// judge range-of-motion / depth at the moment the rep is completed.
  double _romExtreme = 999;

  /// Worst (largest) body-line deviation seen during the current rep.
  double _faultPeak = 0;

  /// Current/last form fault code (see [FormFault]); null when form looks good.
  String? formFault;

  /// Number of reps flagged with a form problem (good-form ratio = clean/total).
  int faultReps = 0;
  int totalRepsTracked = 0;

  void _resetRepTracking() {
    _romExtreme = 999;
    _faultPeak = 0;
  }

  /// Full reset of counters, stages and form-quality tracking.
  void reset() {
    stagePush = null;
    stageSquat = null;
    stageRightCurl = null;
    stageLeftCurl = null;
    stagePress = null;
    pushUps = 0;
    squats = 0;
    bicepCurls = 0;
    shoulderPresses = 0;
    formFault = null;
    faultReps = 0;
    totalRepsTracked = 0;
    _resetRepTracking();
  }

  void _commitRep({required bool clean, String? fault}) {
    totalRepsTracked++;
    if (clean) {
      formFault = null;
    } else {
      faultReps++;
      formFault = fault;
    }
    _resetRepTracking();
  }

  double get goodFormRatio =>
      totalRepsTracked == 0 ? 1.0 : (totalRepsTracked - faultReps) / totalRepsTracked;
}

/// Updates counters and live form feedback from [grid] for a classifier label.
void updateRepsForLabel(
  String label,
  LandmarkPixelGrid grid,
  RepCounterState s,
) {
  final key = label.trim().toLowerCase();
  if (grid.handsJoined()) return;

  if (key.contains('push')) {
    _pushUp(grid, s);
  } else if (key.contains('squat')) {
    _squat(grid, s);
  } else if (key.contains('bicep') || key.contains('curl')) {
    _bicepCurl(grid, s);
  } else if (key.contains('shoulder') && key.contains('press')) {
    _shoulderPress(grid, s);
  }
}

const double _pushDownEnter = 110; // elbow below this = descending
const double _pushUpExit = 150; // elbow above this = locked out
const double _pushGoodDepth = 95; // must reach at least this depth

void _pushUp(LandmarkPixelGrid g, RepCounterState s) {
  final elbow = g.bilateralAngle(11, 13, 15, 12, 14, 16);
  if (elbow < 0) return;

  // Body line: shoulder-hip-knee should stay ~180 (straight plank).
  final bodyLine = g.bilateralAngle(11, 23, 25, 12, 24, 26);
  if (bodyLine >= 0) {
    final dev = (180 - bodyLine).abs();
    if (dev > s._faultPeak) s._faultPeak = dev;
  }

  if (elbow < s._romExtreme) s._romExtreme = elbow;

  if (elbow < _pushDownEnter) {
    s.stagePush = 'down';
  }
  if (elbow > _pushUpExit && s.stagePush == 'down') {
    s.stagePush = 'up';
    s.pushUps++;

    String? fault;
    if (s._romExtreme > _pushGoodDepth) {
      fault = FormFault.partialReps;
    } else if (s._faultPeak > 22) {
      // Hips out of line: decide sag vs pike using hip height vs shoulder/knee.
      fault = _hipDirection(g);
    }
    s._commitRep(clean: fault == null, fault: fault);
  }
}

String _hipDirection(LandmarkPixelGrid g) {
  final sh = _avgY(g, 11, 12);
  final hip = _avgY(g, 23, 24);
  final kn = _avgY(g, 25, 26);
  if (sh == null || hip == null || kn == null) return FormFault.hipSag;
  final line = (sh + kn) / 2;
  // Larger y = lower on screen. Hips below the shoulder-knee line = sagging.
  return hip > line ? FormFault.hipSag : FormFault.hipPike;
}

const double _squatDownEnter = 110; // knee below this = descending
const double _squatUpExit = 155; // knee above this = standing
const double _squatGoodDepth = 100; // parallel-ish target

void _squat(LandmarkPixelGrid g, RepCounterState s) {
  final knee = g.bilateralAngle(23, 25, 27, 24, 26, 28);
  if (knee < 0) return;

  // Torso lean: shoulder→hip tilt from vertical (some lean is fine, a lot isn't).
  final lean = _torsoTilt(g);
  if (lean >= 0 && lean > s._faultPeak) s._faultPeak = lean;

  if (knee < s._romExtreme) s._romExtreme = knee;

  if (knee < _squatDownEnter) {
    s.stageSquat = 'down';
  }
  if (knee > _squatUpExit && s.stageSquat == 'down') {
    s.stageSquat = 'up';
    s.squats++;

    String? fault;
    if (s._romExtreme > _squatGoodDepth) {
      fault = FormFault.shallowSquat;
    } else if (s._faultPeak > 45) {
      fault = FormFault.torsoLean;
    }
    s._commitRep(clean: fault == null, fault: fault);
  }
}

const double _curlDownEnter = 150; // arm extended
const double _curlUpExit = 60; // arm contracted

void _bicepCurl(LandmarkPixelGrid g, RepCounterState s) {
  final elbow = g.bilateralAngle(11, 13, 15, 12, 14, 16);
  if (elbow < 0) return;

  // Swing/torso sway: torso should stay upright through the curl.
  final lean = _torsoTilt(g);
  if (lean >= 0 && lean > s._faultPeak) s._faultPeak = lean;

  if (elbow > _curlDownEnter) {
    s.stageRightCurl = 'down';
  }
  if (elbow < _curlUpExit && s.stageRightCurl == 'down') {
    s.stageRightCurl = 'contracted';
    s.bicepCurls++;

    final fault = s._faultPeak > 18 ? FormFault.swinging : null;
    s._commitRep(clean: fault == null, fault: fault);
  }
}

const double _pressDownEnter = 100; // elbow bent at rack
const double _pressUpExit = 158; // elbow locked overhead

void _shoulderPress(LandmarkPixelGrid g, RepCounterState s) {
  final elbow = g.bilateralAngle(11, 13, 15, 12, 14, 16);
  if (elbow < 0) return;

  // Excessive lower-back arch ≈ big shoulder→hip tilt while pressing.
  final lean = _torsoTilt(g);
  if (lean >= 0 && lean > s._faultPeak) s._faultPeak = lean;

  if (elbow < s._romExtreme) s._romExtreme = elbow;

  if (elbow < _pressDownEnter) {
    s.stagePress = 'down';
  }
  if (elbow > _pressUpExit && s.stagePress == 'down') {
    s.stagePress = 'up';
    s.shoulderPresses++;

    final wristAboveShoulder = _wristAboveShoulder(g);
    String? fault;
    if (!wristAboveShoulder) {
      fault = FormFault.lockout;
    } else if (s._faultPeak > 22) {
      fault = FormFault.backArch;
    }
    s._commitRep(clean: fault == null, fault: fault);
  }
}

double _torsoTilt(LandmarkPixelGrid g) {
  // Average shoulder→hip segment tilt from vertical.
  final left = g.tiltFromVertical(11, 23);
  final right = g.tiltFromVertical(12, 24);
  if (left >= 0 && right >= 0) return (left + right) / 2;
  if (left >= 0) return left;
  if (right >= 0) return right;
  return -1;
}

bool _wristAboveShoulder(LandmarkPixelGrid g) {
  final wrist = _avgY(g, 15, 16);
  final shoulder = _avgY(g, 11, 12);
  if (wrist == null || shoulder == null) return true;
  // Smaller y = higher on screen.
  return wrist < shoulder;
}

double? _avgY(LandmarkPixelGrid g, int a, int b) {
  final pa = g.pts[a];
  final pb = g.pts[b];
  if (pa != null && pb != null) return (pa[1] + pb[1]) / 2;
  if (pa != null) return pa[1];
  if (pb != null) return pb[1];
  return null;
}

int totalRepsForLabel(RepCounterState s, String label) {
  final k = label.toLowerCase();
  if (k.contains('push')) return s.pushUps;
  if (k.contains('squat')) return s.squats;
  if (k.contains('bicep') || k.contains('curl') || k.contains('barbell')) {
    return s.bicepCurls;
  }
  if (k.contains('shoulder')) return s.shoulderPresses;
  return s.pushUps + s.squats + s.bicepCurls + s.shoulderPresses;
}

/// Localized live form-fault line for the current rep (empty when form is good).
String formFaultMessage(String? code, {required bool arabic}) {
  if (code == null) return '';
  final ar = _faultAr[code];
  final en = _faultEn[code];
  return arabic ? (ar ?? '') : (en ?? '');
}

const Map<String, String> _faultEn = {
  FormFault.partialReps: 'Partial rep — go deeper for full range.',
  FormFault.hipSag: 'Hips sagging — squeeze glutes, keep a straight line.',
  FormFault.hipPike: 'Hips too high — lower them in line with your body.',
  FormFault.shallowSquat: 'Too shallow — squat down to at least parallel.',
  FormFault.torsoLean: 'Chest dropping — stay tall, keep torso upright.',
  FormFault.swinging: 'Swinging — lock elbows at your sides, no momentum.',
  FormFault.elbowFlare: 'Elbows flaring — tuck them closer to your body.',
  FormFault.lockout: 'Press fully overhead until arms lock out.',
  FormFault.backArch: 'Lower-back arching — brace your core.',
};

const Map<String, String> _faultAr = {
  FormFault.partialReps: 'تكرار غير كامل — انزل أكتر للمدى الكامل.',
  FormFault.hipSag: 'الحوض هابط — شدّ الأرداف وخلّي جسمك خط مستقيم.',
  FormFault.hipPike: 'الحوض مرفوع زيادة — نزّله في خط مع جسمك.',
  FormFault.shallowSquat: 'النزول قليل — انزل للموازاة على الأقل.',
  FormFault.torsoLean: 'صدرك بيقع — ارفع صدرك وخلّي جذعك مستقيم.',
  FormFault.swinging: 'بتتأرجح — ثبّت المرفقين على جنبك من غير زخم.',
  FormFault.elbowFlare: 'المرفقان مفرودان للخارج — قرّبهم من جسمك.',
  FormFault.lockout: 'افرد ذراعيك بالكامل فوق رأسك.',
  FormFault.backArch: 'أسفل ظهرك بيتقوس — شدّ عضلات بطنك.',
};
