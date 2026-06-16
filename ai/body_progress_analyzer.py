"""
Before/after body progress analyzer — category-aware muscle region comparison.

Uses MediaPipe Pose landmarks + regional definition scores to quantify visible
changes between two progress photos. Designed for shirtless fitness photos.
"""

from __future__ import annotations

import base64
import re
from dataclasses import dataclass, field
from typing import Any

import cv2
import numpy as np

try:
    import mediapipe as mp
except ImportError as e:
    raise ImportError("mediapipe is required: pip install mediapipe opencv-python-headless") from e

# MediaPipe Pose landmark indices
_LS, _RS = 11, 12
_LE, _RE = 13, 14
_LW, _RW = 15, 16
_LH, _RH = 23, 24
_LK, _RK = 25, 26
_LA, _RA = 27, 28
_NOSE = 0

CATEGORIES = ("Strength", "Muscle Gain", "Weight Loss", "Endurance", "Mobility")

# region_id -> weight for each category (primary muscles get higher weight)
CATEGORY_REGION_WEIGHTS: dict[str, dict[str, float]] = {
    "Strength": {
        "shoulders": 1.0,
        "back": 0.9,
        "legs": 0.85,
        "core": 0.7,
        "arms": 0.75,
        "chest": 0.8,
        "waist": 0.3,
        "posture": 0.5,
    },
    "Muscle Gain": {
        "chest": 1.0,
        "arms": 1.0,
        "shoulders": 0.95,
        "back": 0.9,
        "legs": 0.85,
        "core": 0.6,
        "waist": 0.4,
        "posture": 0.4,
    },
    "Weight Loss": {
        "waist": 1.0,
        "core": 0.9,
        "torso_lean": 0.95,
        "legs": 0.6,
        "arms": 0.5,
        "shoulders": 0.4,
        "chest": 0.45,
        "posture": 0.5,
    },
    "Endurance": {
        "legs": 1.0,
        "core": 0.85,
        "torso_lean": 0.8,
        "shoulders": 0.5,
        "arms": 0.45,
        "waist": 0.55,
        "posture": 0.6,
    },
    "Mobility": {
        "posture": 1.0,
        "hips": 0.9,
        "shoulders": 0.75,
        "core": 0.7,
        "legs": 0.55,
        "arms": 0.4,
        "waist": 0.35,
    },
}

# Whether a positive delta in this metric is desirable for the category
# metric_key -> True means higher after value is good
DESIRED_DIRECTION: dict[str, dict[str, bool]] = {
    "Strength": {
        "shoulder_width": True,
        "arm_bulk": True,
        "leg_bulk": True,
        "chest_span": True,
        "definition": True,
        "waist_width": False,
        "posture_score": True,
    },
    "Muscle Gain": {
        "shoulder_width": True,
        "arm_bulk": True,
        "leg_bulk": True,
        "chest_span": True,
        "definition": True,
        "waist_width": False,
        "posture_score": True,
    },
    "Weight Loss": {
        "shoulder_width": False,
        "arm_bulk": False,
        "leg_bulk": False,
        "chest_span": False,
        "definition": True,
        "waist_width": False,
        "posture_score": True,
        "torso_lean": True,
    },
    "Endurance": {
        "shoulder_width": False,
        "arm_bulk": False,
        "leg_bulk": False,
        "chest_span": False,
        "definition": True,
        "waist_width": False,
        "posture_score": True,
        "torso_lean": True,
        "leg_definition": True,
    },
    "Mobility": {
        "shoulder_width": False,
        "arm_bulk": False,
        "leg_bulk": False,
        "chest_span": False,
        "definition": False,
        "waist_width": False,
        "posture_score": True,
        "hip_symmetry": True,
        "shoulder_level": True,
    },
}

REGION_LABELS_EN: dict[str, str] = {
    "shoulders": "Shoulders",
    "back": "Back / Lats",
    "legs": "Legs",
    "core": "Core",
    "arms": "Arms",
    "chest": "Chest",
    "waist": "Waist",
    "posture": "Posture & alignment",
    "hips": "Hips & mobility",
    "torso_lean": "Overall leanness",
}

REGION_LABELS_AR: dict[str, str] = {
    "shoulders": "الأكتاف",
    "back": "الظهر / العضلة العريضة",
    "legs": "الأرجل",
    "core": "الجذع / الكور",
    "arms": "الذراعين",
    "chest": "الصدر",
    "waist": "الخصر",
    "posture": "الوضعية والمحاذاة",
    "hips": "الورك والمرونة",
    "torso_lean": "النحافة العامة",
}


@dataclass
class BodyMetrics:
    shoulder_width: float = 0.0
    arm_bulk: float = 0.0
    leg_bulk: float = 0.0
    chest_span: float = 0.0
    waist_width: float = 0.0
    definition: float = 0.0
    posture_score: float = 0.0
    torso_lean: float = 0.0
    leg_definition: float = 0.0
    hip_symmetry: float = 0.0
    shoulder_level: float = 0.0
    body_height_px: float = 1.0
    pose_confidence: float = 0.0

    def to_dict(self) -> dict[str, float]:
        return {
            "shoulder_width": self.shoulder_width,
            "arm_bulk": self.arm_bulk,
            "leg_bulk": self.leg_bulk,
            "chest_span": self.chest_span,
            "waist_width": self.waist_width,
            "definition": self.definition,
            "posture_score": self.posture_score,
            "torso_lean": self.torso_lean,
            "leg_definition": self.leg_definition,
            "hip_symmetry": self.hip_symmetry,
            "shoulder_level": self.shoulder_level,
            "pose_confidence": self.pose_confidence,
        }


@dataclass
class RegionResult:
    region_id: str
    label: str
    change_percent: float
    score: float  # 0-100 how well change matches category goal
    status: str  # improved | maintained | regressed | unclear
    detail: str


@dataclass
class ComparisonResult:
    category: str
    overall_score: float
    plan_alignment_percent: float
    plan_aligned: bool
    regions: list[RegionResult] = field(default_factory=list)
    summary: str = ""
    before_pose_ok: bool = True
    after_pose_ok: bool = True
    no_measurable_change: bool = False
    metrics_before: dict[str, float] = field(default_factory=dict)
    metrics_after: dict[str, float] = field(default_factory=dict)

    def to_api_dict(self, lang: str = "en") -> dict[str, Any]:
        is_ar = lang.lower().startswith("ar")
        return {
            "category": self.category,
            "overallScore": round(self.overall_score, 1),
            "planAlignmentPercent": round(self.plan_alignment_percent, 1),
            "planAligned": self.plan_aligned,
            "noMeasurableChange": self.no_measurable_change,
            "summary": self.summary,
            "beforePoseDetected": self.before_pose_ok,
            "afterPoseDetected": self.after_pose_ok,
            "regions": [
                {
                    "id": r.region_id,
                    "label": r.label,
                    "changePercent": round(r.change_percent, 1),
                    "score": round(r.score, 1),
                    "status": r.status,
                    "detail": r.detail,
                }
                for r in self.regions
            ],
            "metricsBefore": {k: round(v, 4) for k, v in self.metrics_before.items()},
            "metricsAfter": {k: round(v, 4) for k, v in self.metrics_after.items()},
            "language": "ar" if is_ar else "en",
        }


def _decode_image(b64: str) -> np.ndarray:
    raw = b64.strip()
    if raw.startswith("data:"):
        raw = raw.split(",", 1)[-1]
    data = base64.b64decode(raw)
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Could not decode image")
    return img


def _dist(a: tuple[float, float], b: tuple[float, float]) -> float:
    return float(np.hypot(a[0] - b[0], a[1] - b[1]))


def _mid(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)


def _lm_xy(landmarks, idx: int, w: int, h: int) -> tuple[float, float]:
    lm = landmarks[idx]
    return (lm.x * w, lm.y * h)


def _visibility_avg(landmarks, indices: list[int]) -> float:
    vis = [landmarks[i].visibility for i in indices if hasattr(landmarks[i], "visibility")]
    return float(np.mean(vis)) if vis else 0.0


def _region_definition(gray: np.ndarray, cx: int, cy: int, radius: int) -> float:
    h, w = gray.shape
    x1 = max(0, cx - radius)
    x2 = min(w, cx + radius)
    y1 = max(0, cy - radius)
    y2 = min(h, cy + radius)
    patch = gray[y1:y2, x1:x2]
    if patch.size < 16:
        return 0.0
    lap = cv2.Laplacian(patch, cv2.CV_64F)
    return float(np.var(lap))


def _extract_metrics(image: np.ndarray, pose_landmarks, seg_mask=None) -> BodyMetrics:
    h, w = image.shape[:2]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    lm = pose_landmarks.landmark

    ls = _lm_xy(lm, _LS, w, h)
    rs = _lm_xy(lm, _RS, w, h)
    le = _lm_xy(lm, _LE, w, h)
    re = _lm_xy(lm, _RE, w, h)
    lw = _lm_xy(lm, _LW, w, h)
    rw = _lm_xy(lm, _RW, w, h)
    lh = _lm_xy(lm, _LH, w, h)
    rh = _lm_xy(lm, _RH, w, h)
    lk = _lm_xy(lm, _LK, w, h)
    rk = _lm_xy(lm, _RK, w, h)
    la = _lm_xy(lm, _LA, w, h)
    ra = _lm_xy(lm, _RA, w, h)
    nose = _lm_xy(lm, _NOSE, w, h)

    shoulder_mid = _mid(ls, rs)
    hip_mid = _mid(lh, rh)
    ankle_mid = _mid(la, ra)

    body_h = max(_dist(nose, ankle_mid), _dist(shoulder_mid, ankle_mid), 1.0)
    shoulder_w = _dist(ls, rs) / body_h
    hip_w = _dist(lh, rh) / body_h
    waist_est = (shoulder_w * 0.55 + hip_w * 0.45)
    chest_span = _dist(shoulder_mid, hip_mid) / body_h * shoulder_w

    # --- Silhouette-based widths (real body shape, not just bone length) ---
    # These reflect actual mass/leanness changes far better than landmark
    # distances, so they take priority when a segmentation mask is available.
    if seg_mask is not None and float(np.mean(seg_mask > 0.5)) > 0.02:
        sh_y = int(shoulder_mid[1])
        hip_y = int(hip_mid[1])
        torso_len = max(hip_y - sh_y, 1)
        chest_y0 = sh_y + int(torso_len * 0.15)
        chest_y1 = sh_y + int(torso_len * 0.45)
        waist_y0 = sh_y + int(torso_len * 0.55)
        waist_y1 = hip_y

        sh_width_px = _silhouette_width_at(seg_mask, sh_y, band=5)
        chest_width_px = _max_width_between(seg_mask, chest_y0, chest_y1)
        waist_width_px = _min_width_between(seg_mask, waist_y0, waist_y1)

        if sh_width_px > 0:
            shoulder_w = sh_width_px / body_h
        if chest_width_px > 0:
            chest_span = chest_width_px / body_h
        if waist_width_px > 0:
            waist_est = waist_width_px / body_h

    upper_arm_l = (_dist(ls, le) + _dist(rs, re)) / 2 / body_h
    forearm_l = (_dist(le, lw) + _dist(re, rw)) / 2 / body_h
    arm_bulk = (upper_arm_l + forearm_l) * 0.5 + shoulder_w * 0.15

    thigh_l = (_dist(lh, lk) + _dist(rh, rk)) / 2 / body_h
    calf_l = (_dist(lk, la) + _dist(rk, ra)) / 2 / body_h
    leg_bulk = (thigh_l + calf_l) * 0.5

    # Definition scores from image patches around key joints
    def_pts = [
        (int(ls[0]), int(ls[1]), 28),
        (int(rs[0]), int(rs[1]), 28),
        (int(le[0]), int(le[1]), 22),
        (int(re[0]), int(re[1]), 22),
        (int(lh[0]), int(lh[1]), 30),
        (int(rh[0]), int(rh[1]), 30),
        (int(shoulder_mid[0]), int((shoulder_mid[1] + hip_mid[1]) / 2), 35),
    ]
    defs = [_region_definition(gray, x, y, r) for x, y, r in def_pts]
    definition = float(np.mean(defs)) if defs else 0.0
    leg_def = float(np.mean(defs[4:6])) if len(defs) >= 6 else definition

    # Posture: vertical alignment (nose, shoulder mid, hip mid on same x-axis)
    x_dev = abs(nose[0] - shoulder_mid[0]) + abs(shoulder_mid[0] - hip_mid[0])
    posture = max(0.0, 1.0 - (x_dev / (w * 0.15)))

    shoulder_tilt = abs(ls[1] - rs[1]) / body_h
    shoulder_level = max(0.0, 1.0 - shoulder_tilt * 8)

    hip_tilt = abs(lh[1] - rh[1]) / body_h
    hip_sym = max(0.0, 1.0 - hip_tilt * 8)

    # V-taper: shoulder-to-waist ratio. Rises as the waist shrinks (fat loss)
    # or the shoulders/back widen (muscle gain) — the single most informative
    # physique signal across categories.
    torso_lean = shoulder_w / max(waist_est, 0.01)

    conf = _visibility_avg(lm, [_LS, _RS, _LH, _RH, _LK, _RK, _LA, _RA])

    return BodyMetrics(
        shoulder_width=shoulder_w,
        arm_bulk=arm_bulk,
        leg_bulk=leg_bulk,
        chest_span=chest_span,
        waist_width=waist_est,
        definition=definition,
        posture_score=posture,
        torso_lean=torso_lean,
        leg_definition=leg_def,
        hip_symmetry=hip_sym,
        shoulder_level=shoulder_level,
        body_height_px=body_h,
        pose_confidence=conf,
    )


_pose_detector: mp.solutions.pose.Pose | None = None


def _get_pose_detector() -> mp.solutions.pose.Pose:
    global _pose_detector
    if _pose_detector is None:
        _pose_detector = mp.solutions.pose.Pose(
            static_image_mode=True,
            model_complexity=2,
            # Segmentation lets us measure the real body silhouette width
            # (shoulders / chest / waist) instead of just bone lengths.
            enable_segmentation=True,
            min_detection_confidence=0.5,
        )
    return _pose_detector


def analyze_single_image(b64: str) -> tuple[BodyMetrics | None, bool]:
    image = _decode_image(b64)
    rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    detector = _get_pose_detector()
    result = detector.process(rgb)
    if not result.pose_landmarks:
        return None, False
    seg = getattr(result, "segmentation_mask", None)
    metrics = _extract_metrics(image, result.pose_landmarks, seg)
    return metrics, True


def _silhouette_width_at(mask: np.ndarray, y: int, band: int = 4) -> float:
    """Horizontal extent (px) of the body silhouette around row [y]."""
    h, w = mask.shape
    y0 = max(0, y - band)
    y1 = min(h, y + band + 1)
    if y1 <= y0:
        return 0.0
    region = mask[y0:y1, :] > 0.5
    cols = np.where(region.any(axis=0))[0]
    if cols.size < 2:
        return 0.0
    return float(cols[-1] - cols[0])


def _min_width_between(mask: np.ndarray, y_top: int, y_bot: int, samples: int = 7) -> float:
    """Narrowest silhouette width in the band — approximates the true waist."""
    if y_bot <= y_top:
        return 0.0
    ys = np.linspace(y_top, y_bot, samples).astype(int)
    widths = [w for w in (_silhouette_width_at(mask, int(y), 2) for y in ys) if w > 0]
    return float(min(widths)) if widths else 0.0


def _max_width_between(mask: np.ndarray, y_top: int, y_bot: int, samples: int = 7) -> float:
    if y_bot <= y_top:
        return 0.0
    ys = np.linspace(y_top, y_bot, samples).astype(int)
    widths = [w for w in (_silhouette_width_at(mask, int(y), 2) for y in ys) if w > 0]
    return float(max(widths)) if widths else 0.0


def _delta_pct(before: float, after: float) -> float:
    if abs(before) < 1e-6:
        return 0.0 if abs(after) < 1e-6 else 100.0
    return ((after - before) / abs(before)) * 100.0


def _metric_score(category: str, metric_key: str, delta: float) -> tuple[float, str]:
    """Return 0-100 score and status for a metric change."""
    desired_up = DESIRED_DIRECTION.get(category, {}).get(metric_key, True)
    if abs(delta) < 2.0:
        return 55.0, "maintained"

    if desired_up:
        if delta > 2:
            return min(100.0, 60 + delta * 2), "improved"
        if delta < -2:
            return max(0.0, 40 + delta * 2), "regressed"
    else:
        if delta < -2:
            return min(100.0, 60 + abs(delta) * 2), "improved"
        if delta > 2:
            return max(0.0, 40 - delta * 2), "regressed"
    return 50.0, "unclear"


# Maps region_id -> list of metric keys
REGION_METRICS: dict[str, list[str]] = {
    "shoulders": ["shoulder_width", "shoulder_level"],
    "back": ["shoulder_width", "definition"],
    "legs": ["leg_bulk", "leg_definition"],
    "core": ["definition", "posture_score"],
    "arms": ["arm_bulk", "definition"],
    "chest": ["chest_span", "definition"],
    "waist": ["waist_width", "torso_lean"],
    "posture": ["posture_score", "shoulder_level"],
    "hips": ["hip_symmetry", "posture_score"],
    "torso_lean": ["torso_lean", "waist_width", "definition"],
}


def _region_detail(region_id: str, delta: float, status: str, lang: str) -> str:
    is_ar = lang.lower().startswith("ar")
    label = REGION_LABELS_AR.get(region_id, region_id) if is_ar else REGION_LABELS_EN.get(region_id, region_id)
    if is_ar:
        if status == "improved":
            return f"تحسّن واضح في {label} (تغيّر تقريبي {delta:+.1f}%)"
        if status == "regressed":
            return f"تراجع طفيف في {label} ({delta:+.1f}%)"
        if status == "maintained":
            return f"ثبات نسبي في {label}"
        return f"تغيّر غير حاسم في {label} ({delta:+.1f}%)"
    if status == "improved":
        return f"Visible improvement in {label} (~{delta:+.1f}% change)"
    if status == "regressed":
        return f"Slight regression in {label} ({delta:+.1f}%)"
    if status == "maintained":
        return f"Relatively stable {label}"
    return f"Inconclusive change in {label} ({delta:+.1f}%)"


def _images_identical(before_b64: str, after_b64: str) -> bool:
    b = strip_data_url(before_b64)
    a = strip_data_url(after_b64)
    if b == a:
        return True
    try:
        img_b = _decode_image(before_b64)
        img_a = _decode_image(after_b64)
        if img_b.shape != img_a.shape:
            return False
        diff = float(np.mean(np.abs(img_b.astype(np.int16) - img_a.astype(np.int16))))
        return diff < 2.0
    except Exception:
        return False


def _all_metrics_stable(b: dict[str, float], a: dict[str, float], threshold: float = 2.5) -> bool:
    keys = [k for k in b if k not in ("pose_confidence",) and k in a]
    if not keys:
        return False
    return all(abs(_delta_pct(b[k], a[k])) < threshold for k in keys)


def _no_change_result(
    display_cat: str,
    weights_cat: str,
    before_m: BodyMetrics,
    after_m: BodyMetrics,
    lang: str,
) -> ComparisonResult:
    """Same (or effectively identical) photos — report stability, not fake improvement."""
    is_ar = lang.lower().startswith("ar")
    labels = REGION_LABELS_AR if is_ar else REGION_LABELS_EN
    weights = CATEGORY_REGION_WEIGHTS.get(weights_cat, CATEGORY_REGION_WEIGHTS["Muscle Gain"])
    regions: list[RegionResult] = []

    for region_id, w in sorted(weights.items(), key=lambda x: -x[1]):
        if w < 0.35:
            continue
        label = labels.get(region_id, region_id)
        detail = (
            f"ثبات في {label} — لا يوجد فرق قابل للقياس بين الصورتين"
            if is_ar
            else f"Stable {label} — no measurable difference between the two photos"
        )
        regions.append(
            RegionResult(
                region_id=region_id,
                label=label,
                change_percent=0.0,
                score=50.0,
                status="maintained",
                detail=detail,
            )
        )

    summary = (
        f"لا يوجد تغيّر قابل للقياس بين صورتي «قبل» و«بعد». النتيجة {50:.0f}/100 (خط أساس — ثبات)."
        if is_ar
        else (
            "No measurable change between the BEFORE and AFTER photos. "
            f"Score {50:.0f}/100 (baseline — stable physique)."
        )
    )

    return ComparisonResult(
        category=display_cat,
        overall_score=50.0,
        plan_alignment_percent=0.0,
        plan_aligned=True,
        regions=regions,
        summary=summary,
        before_pose_ok=True,
        after_pose_ok=True,
        no_measurable_change=True,
        metrics_before=before_m.to_dict(),
        metrics_after=after_m.to_dict(),
    )


def _build_summary(
    category: str,
    overall: float,
    aligned: bool,
    regions: list[RegionResult],
    lang: str,
) -> str:
    is_ar = lang.lower().startswith("ar")
    improved = [r for r in regions if r.status == "improved"]
    regressed = [r for r in regions if r.status == "regressed"]

    if is_ar:
        parts = [
            f"تقييم التقدم لخطة «{category}»: {overall:.0f}/100.",
            "النتيجة متوافقة مع أهداف الخطة." if aligned else "بعض المناطق لا تتوافق بعد مع أهداف الخطة.",
        ]
        if improved:
            parts.append(f"أفضل تحسّن: {improved[0].label}.")
        if regressed:
            parts.append(f"يحتاج انتباه: {regressed[0].label}.")
        return " ".join(parts)

    parts = [
        f"Progress score for {category} plan: {overall:.0f}/100.",
        "Results align with your plan goals." if aligned else "Some areas still don't match your plan targets.",
    ]
    if improved:
        parts.append(f"Best improvement: {improved[0].label}.")
    if regressed:
        parts.append(f"Needs attention: {regressed[0].label}.")
    return " ".join(parts)


def compare_before_after(
    before_b64: str,
    after_b64: str,
    category: str,
    lang: str = "en",
    template_category: str | None = None,
) -> ComparisonResult:
    display_cat = (category or "").strip() or "Muscle Gain"
    template = (template_category or "").strip()
    weights_cat = (
        template
        if template in CATEGORIES
        else (display_cat if display_cat in CATEGORIES else "Muscle Gain")
    )
    is_ar = lang.lower().startswith("ar")

    before_m, before_ok = analyze_single_image(before_b64)
    after_m, after_ok = analyze_single_image(after_b64)

    if not before_ok or before_m is None:
        raise ValueError(
            "لم نتمكن من اكتشاف الجسم في صورة «قبل». التقط صورة واضحة للجسم كاملًا من الأمام."
            if is_ar
            else "Could not detect body pose in BEFORE photo. Use a clear full-body front photo."
        )
    if not after_ok or after_m is None:
        raise ValueError(
            "لم نتمكن من اكتشاف الجسم في صورة «بعد». التقط صورة واضحة للجسم كاملًا من الأمام."
            if is_ar
            else "Could not detect body pose in AFTER photo. Use a clear full-body front photo."
        )

    b = before_m.to_dict()
    a = after_m.to_dict()

    if _images_identical(before_b64, after_b64) or _all_metrics_stable(b, a):
        return _no_change_result(display_cat, weights_cat, before_m, after_m, lang)

    weights = CATEGORY_REGION_WEIGHTS.get(weights_cat, CATEGORY_REGION_WEIGHTS["Muscle Gain"])

    regions: list[RegionResult] = []
    weighted_scores: list[float] = []
    weight_sum = 0.0
    aligned_count = 0
    primary_count = 0

    labels = REGION_LABELS_AR if is_ar else REGION_LABELS_EN

    for region_id, w in sorted(weights.items(), key=lambda x: -x[1]):
        if w < 0.35:
            continue
        metric_keys = REGION_METRICS.get(region_id, ["definition"])
        deltas: list[float] = []
        scores: list[float] = []
        statuses: list[str] = []
        for mk in metric_keys:
            if mk not in b or mk not in a:
                continue
            d = _delta_pct(b[mk], a[mk])
            sc, st = _metric_score(weights_cat, mk, d)
            deltas.append(d)
            scores.append(sc)
            statuses.append(st)

        if not deltas:
            continue

        avg_delta = float(np.mean(deltas))
        avg_score = float(np.mean(scores))
        # majority status
        status = max(set(statuses), key=statuses.count)
        label = labels.get(region_id, region_id)
        detail = _region_detail(region_id, avg_delta, status, lang)

        regions.append(
            RegionResult(
                region_id=region_id,
                label=label,
                change_percent=avg_delta,
                score=avg_score,
                status=status,
                detail=detail,
            )
        )
        weighted_scores.append(avg_score * w)
        weight_sum += w
        primary_count += 1
        if status == "improved":
            aligned_count += 1
        elif status == "maintained" and abs(avg_delta) < 2.0:
            aligned_count += 1

    overall = float(np.sum(weighted_scores) / weight_sum) if weight_sum else 50.0
    alignment_pct = (aligned_count / primary_count * 100) if primary_count else 0.0
    plan_aligned = alignment_pct >= 55.0

    summary = _build_summary(display_cat, overall, plan_aligned, regions, lang)

    return ComparisonResult(
        category=display_cat,
        overall_score=overall,
        plan_alignment_percent=alignment_pct,
        plan_aligned=plan_aligned,
        regions=regions,
        summary=summary,
        before_pose_ok=before_ok,
        after_pose_ok=after_ok,
        metrics_before=b,
        metrics_after=a,
    )


def strip_data_url(b64: str) -> str:
    s = (b64 or "").strip()
    if s.startswith("data:"):
        return s.split(",", 1)[-1]
    return s
