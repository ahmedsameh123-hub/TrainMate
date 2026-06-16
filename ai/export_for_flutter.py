"""
تصدير موديل التصنيف (Keras + joblib) إلى صيغة يقرأها Flutter: TFLite + JSON.

المتطلبات: tensorflow، joblib، numpy — نفس بيئة تدريب المشروع.

الاستخدام (من مجلد "ai" بعد وضع الملفات في models/):
    python export_for_flutter.py
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MODELS = ROOT / "models"
OUT = ROOT.parent / "trainmate_app" / "assets" / "models"

H5_NAME = "final_forthesis_bidirectionallstm_and_encoders_exercise_classifier_model.h5"
SCALER_NAME = "thesis_bidirectionallstm_scaler.pkl"
ENCODER_NAME = "thesis_bidirectionallstm_label_encoder.pkl"


def main() -> int:
    h5 = MODELS / H5_NAME
    pkl_s = MODELS / SCALER_NAME
    pkl_e = MODELS / ENCODER_NAME

    missing = [str(p) for p in (h5, pkl_s, pkl_e) if not p.is_file()]
    if missing:
        print("ملفات ناقصة في models/:\n", "\n".join(missing))
        return 1

    import joblib
    import numpy as np
    import tensorflow as tf

    scaler = joblib.load(pkl_s)
    enc = joblib.load(pkl_e)

    if hasattr(scaler, "mean_") and hasattr(scaler, "scale_"):
        mean = np.asarray(scaler.mean_, dtype=np.float64).ravel().tolist()
        scale = np.asarray(scaler.scale_, dtype=np.float64).ravel().tolist()
    else:
        print("نوع الـ scaler غير مدعوم تلقائياً (يتوقع StandardScaler). عدّل السكربت يدوياً.")
        return 1

    classes = [str(x) for x in enc.classes_.tolist()]

    OUT.mkdir(parents=True, exist_ok=True)

    meta = {
        "window_size": 30,
        "n_features_per_frame": 22,
        "n_flat": len(mean),
        "mean": mean,
        "scale": scale,
    }
    (OUT / "scaler_params.json").write_text(json.dumps(meta), encoding="utf-8")
    (OUT / "classes.json").write_text(json.dumps(classes), encoding="utf-8")

    # BiLSTM: usually needs SELECT_TF_OPS + disabling tensor-list lowering (fixes LLVM "missing attribute 'value'")
    saved_dir = OUT / "_tmp_saved_model"
    shutil.rmtree(saved_dir, ignore_errors=True)
    saved_dir.mkdir(parents=True, exist_ok=True)
    m0 = tf.keras.models.load_model(str(h5))
    tf.saved_model.save(m0, str(saved_dir))

    def try_from_saved(
        *,
        use_select_tf_ops: bool,
        optimize: bool,
        lower_tensor_list: bool,
    ) -> bytes:
        conv = tf.lite.TFLiteConverter.from_saved_model(str(saved_dir))
        if use_select_tf_ops:
            conv.target_spec.supported_ops = [
                tf.lite.OpsSet.TFLITE_BUILTINS,
                tf.lite.OpsSet.SELECT_TF_OPS,
            ]
        if hasattr(conv, "_experimental_lower_tensor_list_ops"):
            conv._experimental_lower_tensor_list_ops = lower_tensor_list
        conv.optimizations = [tf.lite.Optimize.DEFAULT] if optimize else []
        return conv.convert()

    tflite_bytes: bytes | None = None
    last_err: Exception | None = None
    # Attempt order: the most LSTM-compatible options first
    for lower_tl in (False, True):
        for use_select in (True, False):
            for optimize in (False, True):
                try:
                    tflite_bytes = try_from_saved(
                        use_select_tf_ops=use_select,
                        optimize=optimize,
                        lower_tensor_list=lower_tl,
                    )
                    print(
                        "TFLite OK: saved_model، "
                        f"select_tf_ops={use_select}, optimize={optimize}, "
                        f"lower_tensor_list_ops={lower_tl}. "
                        "إذا select_tf_ops=true أضف tensorflow-lite-select-tf-ops في Android."
                    )
                    break
                except Exception as e:
                    last_err = e
                    print(
                        f"فشل (select={use_select}, opt={optimize}, lower_tl={lower_tl}): {e}"
                    )
            if tflite_bytes is not None:
                break
        if tflite_bytes is not None:
            break

    shutil.rmtree(saved_dir, ignore_errors=True)

    if tflite_bytes is None:
        print("فشل كل محاولات التحويل إلى TFLite.", last_err)
        print(
            "جرّب تشغيل نفس السكربت على Linux/WSL أو TensorFlow 2.13.x، "
            "أو حوّل الموديل يدويًا عبر TensorFlow Model Converter."
        )
        return 1

    out_tflite = OUT / "exercise_classifier.tflite"
    out_tflite.write_bytes(tflite_bytes)

    print("تم التصدير إلى:")
    print(" ", OUT)
    print("  - exercise_classifier.tflite")
    print("  - scaler_params.json")
    print("  - classes.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
