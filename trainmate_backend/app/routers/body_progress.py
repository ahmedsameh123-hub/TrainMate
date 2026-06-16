"""Before/after body comparison — category-aware AI analysis."""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserPlan, UserProfile, WorkoutPlan
from app.routers.chat import _pick_provider, _provider_ready, _supports_vision

router = APIRouter(prefix="/ml", tags=["ml"])

_analyzer_module = None


def _load_analyzer():
    global _analyzer_module
    if _analyzer_module is not None:
        return _analyzer_module

    here = Path(__file__).resolve()
    analyzer_path = here.parents[3] / "ai" / "body_progress_analyzer.py"
    if not analyzer_path.is_file():
        raise RuntimeError(f"body_progress_analyzer.py not found at {analyzer_path}")

    spec = importlib.util.spec_from_file_location("body_progress_analyzer", analyzer_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("Failed to load body progress analyzer module")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["body_progress_analyzer"] = mod
    spec.loader.exec_module(mod)
    _analyzer_module = mod
    return mod


class BodyComparisonIn(BaseModel):
    model_config = {"populate_by_name": True}

    before_photo_base64: str | None = Field(default=None, alias="beforePhotoBase64")
    after_photo_base64: str | None = Field(default=None, alias="afterPhotoBase64")
    category: str | None = None
    template_category: str | None = Field(default=None, alias="templateCategory")
    language_code: str = Field(default="en", alias="languageCode")
    use_vision_enhancement: bool = Field(default=True, alias="useVisionEnhancement")


class BodyRegionOut(BaseModel):
    id: str
    label: str
    change_percent: float = Field(alias="changePercent")
    score: float
    status: str
    detail: str

    model_config = {"populate_by_name": True}


class BodyComparisonOut(BaseModel):
    category: str
    overall_score: float = Field(alias="overallScore")
    plan_alignment_percent: float = Field(alias="planAlignmentPercent")
    plan_aligned: bool = Field(alias="planAligned")
    summary: str
    narrative: str | None = None
    before_pose_detected: bool = Field(alias="beforePoseDetected")
    after_pose_detected: bool = Field(alias="afterPoseDetected")
    regions: list[BodyRegionOut]
    language: str

    model_config = {"populate_by_name": True}


def _vision_model() -> str:
    provider = _pick_provider()
    if provider == "openrouter":
        m = (settings.openrouter_model or "").strip() or "openai/gpt-4o-mini"
        if _supports_vision(m):
            return m
        return "openai/gpt-4o-mini"
    return (settings.openrouter_model or "").strip() or "openai/gpt-4o-mini"


def _enhance_with_vision(
    before_b64: str,
    after_b64: str,
    category: str,
    cv_result: dict,
    lang: str,
) -> str | None:
    if not _provider_ready("openrouter"):
        return None
    is_ar = lang.lower().startswith("ar")
    model = _vision_model()
    if not _supports_vision(model):
        return None

    prompt = (
        f"أنت مدرب لياقة محترف. قارن صورتي التقدم (قبل/بعد) لخطة «{category}». "
        f"التحليل الحاسوبي: {json.dumps(cv_result, ensure_ascii=False)}. "
        "اكتب 3-4 جمل: هل التغيير يتوافق مع أهداف الكاتيجوري؟ أي عضلات تحسّنت؟ نصيحة واحدة. "
        "كن دقيقًا ومحترمًا. لا تخترع تفاصيل غير ظاهرة."
        if is_ar
        else (
            f"You are a professional fitness coach. Compare my before/after progress photos "
            f"for the «{category}» plan. Computer vision metrics: {json.dumps(cv_result)}. "
            "Write 3-4 sentences: does the change match the category goals? which muscles improved? "
            "one actionable tip. Be accurate and respectful. Do not invent details not visible."
        )
    )

    messages: list[dict[str, object]] = [
        {"role": "system", "content": "Expert fitness body-composition analyst. Plain text only."},
        {
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{before_b64}"},
                },
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/jpeg;base64,{after_b64}"},
                },
            ],
        },
    ]

    try:
        openai_mod = __import__("openai")
        client = openai_mod.OpenAI(
            api_key=settings.openrouter_api_key.strip(),
            base_url=(settings.openrouter_base_url or "").strip() or "https://openrouter.ai/api/v1",
        )
        resp = client.chat.completions.create(
            model=model,
            messages=messages,  # type: ignore[arg-type]
            temperature=0.2,
            max_tokens=400,
        )
        text = (resp.choices[0].message.content or "").strip()
        return text or None
    except Exception:
        return None


@router.post("/body-comparison", response_model=BodyComparisonOut, response_model_by_alias=True)
def body_comparison(
    body: BodyComparisonIn,
    lang: str = Query(default="en"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    language = (body.language_code or lang or "en").strip()
    legacy_plan = user.plan
    active_wp = db.scalar(
        select(WorkoutPlan).where(
            WorkoutPlan.user_id == user.id,
            WorkoutPlan.is_active == 1,
            WorkoutPlan.completed_at.is_(None),
        )
    )

    before = (body.before_photo_base64 or "").strip()
    after = (body.after_photo_base64 or "").strip()
    if not before:
        if active_wp and active_wp.before_photo_base64:
            before = active_wp.before_photo_base64.strip()
        elif legacy_plan and legacy_plan.before_photo_base64:
            before = legacy_plan.before_photo_base64.strip()
    if not after:
        if active_wp and active_wp.after_photo_base64:
            after = active_wp.after_photo_base64.strip()
        elif legacy_plan and legacy_plan.after_photo_base64:
            after = legacy_plan.after_photo_base64.strip()

    if not before or not after:
        is_ar = language.lower().startswith("ar")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "يلزم رفع صورتي قبل وبعد لتحليل التقدم."
                if is_ar
                else "Both before and after photos are required for progress analysis."
            ),
        )

    category = (
        body.category
        or (active_wp.template_category if active_wp and active_wp.template_category else None)
        or (legacy_plan.category if legacy_plan else None)
        or "Muscle Gain"
    ).strip()
    template = (body.template_category or "").strip() or (
        active_wp.template_category if active_wp and active_wp.template_category else category
    )

    try:
        analyzer = _load_analyzer()
        before = analyzer.strip_data_url(before)
        after = analyzer.strip_data_url(after)
        result = analyzer.compare_before_after(
            before,
            after,
            category,
            language,
            template_category=template,
        )
        api_dict = result.to_api_dict(language)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e)) from e
    except ImportError as e:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Body analyzer dependencies missing: {e!s}. pip install mediapipe opencv-python-headless",
        ) from e
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Analysis failed: {e!s}",
        ) from e

    narrative: str | None = None
    if body.use_vision_enhancement:
        narrative = _enhance_with_vision(before, after, category, api_dict, language)

    return BodyComparisonOut(
        category=api_dict["category"],
        overall_score=api_dict["overallScore"],
        plan_alignment_percent=api_dict["planAlignmentPercent"],
        plan_aligned=api_dict["planAligned"],
        summary=api_dict["summary"],
        narrative=narrative,
        before_pose_detected=api_dict["beforePoseDetected"],
        after_pose_detected=api_dict["afterPoseDetected"],
        regions=[BodyRegionOut(**r) for r in api_dict["regions"]],
        language=api_dict["language"],
    )
