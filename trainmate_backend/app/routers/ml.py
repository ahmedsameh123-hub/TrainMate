"""استدلال موديل التمارين على السيرفر عندما لا يتوفر TFLite في التطبيق."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from app.config import settings
from app.deps import get_current_user
from app.models import User

router = APIRouter(prefix="/ml", tags=["ml"])

H5_NAME = "final_forthesis_bidirectionallstm_and_encoders_exercise_classifier_model.h5"
SCALER_NAME = "thesis_bidirectionallstm_scaler.pkl"
ENCODER_NAME = "thesis_bidirectionallstm_label_encoder.pkl"

_WINDOW = 30
_N_FRAME = 22

_model = None
_scaler = None
_enc = None


def _models_dir() -> Path:
    if getattr(settings, "ml_models_dir", None) and str(settings.ml_models_dir).strip():
        return Path(settings.ml_models_dir).expanduser().resolve()
    here = Path(__file__).resolve()
    pp_root = here.parents[3]
    return (pp_root / "ai" / "models").resolve()


def _files_present() -> bool:
    d = _models_dir()
    return (
        (d / H5_NAME).is_file()
        and (d / SCALER_NAME).is_file()
        and (d / ENCODER_NAME).is_file()
    )


def _load_keras():
    global _model, _scaler, _enc
    if _model is not None:
        return
    if not _files_present():
        raise RuntimeError(f"ML model files missing under {_models_dir()}")
    try:
        import joblib
        import tensorflow as tf
    except ImportError as e:
        raise RuntimeError(
            "ML extras not installed. Run: pip install -r requirements-ml.txt"
        ) from e

    d = _models_dir()
    _scaler = joblib.load(d / SCALER_NAME)
    _enc = joblib.load(d / ENCODER_NAME)
    _model = tf.keras.models.load_model(str(d / H5_NAME))


class MlStatusOut(BaseModel):
    available: bool
    models_dir: str


class MlClassifyIn(BaseModel):
    window: list[list[float]] = Field(..., description="30×22 pose features (same order as training)")


class MlClassifyOut(BaseModel):
    label: str


@router.get("/status", response_model=MlStatusOut)
def ml_status():
    d = _models_dir()
    return MlStatusOut(available=_files_present(), models_dir=str(d))


@router.post("/classify", response_model=MlClassifyOut)
def classify(body: MlClassifyIn, user: User = Depends(get_current_user)):
    w = body.window
    if len(w) != _WINDOW:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Expected {_WINDOW} frames, got {len(w)}",
        )
    for i, row in enumerate(w):
        if len(row) != _N_FRAME:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Frame {i}: expected {_N_FRAME} features, got {len(row)}",
            )

    try:
        _load_keras()
        import numpy as np
    except RuntimeError as e:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(e)) from e
    except ImportError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="ML extras not installed. Run: pip install -r requirements-ml.txt",
        ) from e

    arr = np.asarray(w, dtype=np.float32).reshape(1, -1)
    try:
        X = _scaler.transform(arr)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Scaler failed: {e!s}",
        ) from e

    X3 = X.reshape(1, _WINDOW, _N_FRAME)
    try:
        logits = _model.predict(X3, verbose=0)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Model inference failed: {e!s}",
        ) from e

    idx = int(np.argmax(logits[0]))
    label = str(_enc.classes_[idx])
    return MlClassifyOut(label=label)
