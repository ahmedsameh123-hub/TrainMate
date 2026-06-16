"""User workout plans — list, create, activate, complete, delete."""

from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_user
from app.models import User, UserPlan, WorkoutPlan, WorkoutSession
from app.routers.body_progress import _load_analyzer
from app.schemas import (
    PlanCompleteRequest,
    PlanCompletionOut,
    PlanCompletionStatsOut,
    PlanExerciseStatOut,
    WorkoutPlanCreate,
    WorkoutPlanOut,
    WorkoutPlanUpdate,
)

router = APIRouter(prefix="/users/me/plans", tags=["plans"])

# Only the exercises the app actually supports (must match
# trainmate_app/assets/models/classes.json and PlanTemplates).
TEMPLATE_EXERCISES: dict[str, list[str]] = {
    "Strength": ["squat", "shoulder press", "push-up"],
    "Muscle Gain": ["push-up", "barbell biceps curl", "shoulder press", "squat"],
    "Weight Loss": ["squat", "push-up"],
    "Endurance": ["push-up", "squat", "shoulder press"],
    "Mobility": ["squat", "push-up"],
}

DEFAULT_DAYS_PER_WEEK = 3


def _parse_exercises(raw: str) -> list[str]:
    try:
        data = json.loads(raw or "[]")
        if isinstance(data, list):
            return [str(x).strip() for x in data if str(x).strip()]
    except json.JSONDecodeError:
        pass
    return []


def _effective_target(row: WorkoutPlan) -> int:
    if row.target_sessions is not None and row.target_sessions > 0:
        return row.target_sessions
    return max(row.duration_weeks * DEFAULT_DAYS_PER_WEEK, 1)


def _sessions_completed(db: Session, plan_id: int) -> int:
    return int(
        db.scalar(
            select(func.count())
            .select_from(WorkoutSession)
            .where(WorkoutSession.plan_id == plan_id)
        )
        or 0
    )


def _plan_out(row: WorkoutPlan, db: Session) -> WorkoutPlanOut:
    completed = _sessions_completed(db, row.id)
    target = _effective_target(row)
    return WorkoutPlanOut(
        id=row.id,
        name=row.name,
        plan_kind=row.plan_kind,
        template_category=row.template_category,
        exercises=_parse_exercises(row.exercises_json),
        duration_weeks=row.duration_weeks,
        before_photo_base64=row.before_photo_base64,
        after_photo_base64=row.after_photo_base64,
        is_active=bool(row.is_active),
        target_sessions=target,
        sessions_completed=completed,
        is_completed=row.completed_at is not None,
        completed_at=row.completed_at.isoformat() if row.completed_at else None,
        completion_percent=row.completion_percent,
        ai_overall_score=row.ai_overall_score,
        ai_alignment_percent=row.ai_alignment_percent,
        created_at=row.created_at.isoformat() if row.created_at else None,
    )


def _sync_legacy_user_plan(user: User, wp: WorkoutPlan, db: Session, *, onboarding: bool | None = None) -> None:
    legacy = user.plan
    if legacy is None:
        legacy = UserPlan(user_id=user.id)
        db.add(legacy)
        db.flush()
    legacy.category = wp.name
    legacy.duration_weeks = wp.duration_weeks
    legacy.before_photo_base64 = wp.before_photo_base64
    legacy.after_photo_base64 = wp.after_photo_base64
    if onboarding is not None:
        legacy.onboarding_completed = 1 if onboarding else 0
    elif wp.before_photo_base64:
        legacy.onboarding_completed = 1


def _deactivate_all(user_id: int, db: Session) -> None:
    rows = db.scalars(select(WorkoutPlan).where(WorkoutPlan.user_id == user_id)).all()
    for r in rows:
        r.is_active = 0


def _resolve_exercises(body: WorkoutPlanCreate) -> list[str]:
    if body.exercises:
        return [e.strip() for e in body.exercises if e.strip()]
    if body.plan_kind == "template" and body.template_category:
        return list(TEMPLATE_EXERCISES.get(body.template_category, TEMPLATE_EXERCISES["Muscle Gain"]))
    return list(TEMPLATE_EXERCISES["Muscle Gain"])


def _resolve_target(body: WorkoutPlanCreate) -> int:
    if body.target_sessions is not None and body.target_sessions > 0:
        return body.target_sessions
    return max(body.duration_weeks * DEFAULT_DAYS_PER_WEEK, 1)


def _aggregate_stats(db: Session, plan_id: int) -> PlanCompletionStatsOut:
    rows = db.scalars(
        select(WorkoutSession).where(WorkoutSession.plan_id == plan_id)
    ).all()

    by_ex: dict[str, dict] = {}
    total_reps = 0
    total_kcal = 0.0
    total_dur = 0
    has_kcal = False

    for r in rows:
        key = r.exercise_label.strip().lower()
        if key not in by_ex:
            by_ex[key] = {"exercise": r.exercise_label, "sessions": 0, "total_reps": 0, "total_kcal": 0.0}
        by_ex[key]["sessions"] += 1
        by_ex[key]["total_reps"] += r.reps
        total_reps += r.reps
        if r.estimated_kcal is not None:
            by_ex[key]["total_kcal"] += r.estimated_kcal
            total_kcal += r.estimated_kcal
            has_kcal = True
        if r.duration_sec is not None:
            total_dur += r.duration_sec

    by_list = [
        PlanExerciseStatOut(
            exercise=v["exercise"],
            sessions=v["sessions"],
            total_reps=v["total_reps"],
            total_kcal=round(v["total_kcal"], 1) if has_kcal else None,
        )
        for v in by_ex.values()
    ]
    by_list.sort(key=lambda x: -x.sessions)

    return PlanCompletionStatsOut(
        total_sessions=len(rows),
        total_reps=total_reps,
        total_kcal=round(total_kcal, 1) if has_kcal else None,
        total_duration_sec=total_dur if total_dur > 0 else None,
        by_exercise=by_list,
    )


@router.get("", response_model=list[WorkoutPlanOut])
def list_plans(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(WorkoutPlan)
        .where(WorkoutPlan.user_id == user.id, WorkoutPlan.completed_at.is_(None))
        .order_by(WorkoutPlan.is_active.desc(), WorkoutPlan.created_at.desc())
    ).all()
    return [_plan_out(r, db) for r in rows]


@router.get("/completed", response_model=list[WorkoutPlanOut])
def list_completed_plans(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.scalars(
        select(WorkoutPlan)
        .where(WorkoutPlan.user_id == user.id, WorkoutPlan.completed_at.isnot(None))
        .order_by(WorkoutPlan.completed_at.desc())
    ).all()
    return [_plan_out(r, db) for r in rows]


@router.post("", response_model=WorkoutPlanOut, status_code=status.HTTP_201_CREATED)
def create_plan(
    body: WorkoutPlanCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    name = body.name.strip()
    if len(name) < 2:
        raise HTTPException(status_code=400, detail="Plan name must be at least 2 characters")

    exercises = _resolve_exercises(body)
    if not exercises:
        raise HTTPException(status_code=400, detail="Select at least one exercise")

    activate = body.activate if body.activate is not None else True
    if activate:
        _deactivate_all(user.id, db)

    kind = (body.plan_kind or "custom").strip().lower()
    if kind not in {"template", "custom"}:
        kind = "custom"

    template = (body.template_category or "").strip() or None
    if kind == "template" and not template:
        template = name if name in TEMPLATE_EXERCISES else "Muscle Gain"

    row = WorkoutPlan(
        user_id=user.id,
        name=name,
        plan_kind=kind,
        template_category=template,
        exercises_json=json.dumps(exercises),
        duration_weeks=body.duration_weeks,
        before_photo_base64=body.before_photo_base64,
        after_photo_base64=body.after_photo_base64,
        target_sessions=_resolve_target(body),
        is_active=1 if activate else 0,
    )
    db.add(row)
    db.flush()

    if activate:
        _sync_legacy_user_plan(user, row, db, onboarding=body.onboarding_completed)

    db.commit()
    db.refresh(row)
    return _plan_out(row, db)


@router.patch("/{plan_id}", response_model=WorkoutPlanOut)
def update_plan(
    plan_id: int,
    body: WorkoutPlanUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    if row.completed_at is not None:
        raise HTTPException(status_code=400, detail="Cannot edit a completed plan")

    data = body.model_dump(exclude_unset=True)
    if "name" in data and data["name"] is not None:
        row.name = data["name"].strip()
    if "exercises" in data and data["exercises"] is not None:
        ex = [e.strip() for e in data["exercises"] if e.strip()]
        if not ex:
            raise HTTPException(status_code=400, detail="Select at least one exercise")
        row.exercises_json = json.dumps(ex)
    if "duration_weeks" in data and data["duration_weeks"] is not None:
        row.duration_weeks = data["duration_weeks"]
    if "before_photo_base64" in data:
        row.before_photo_base64 = data["before_photo_base64"]
    if "after_photo_base64" in data:
        row.after_photo_base64 = data["after_photo_base64"]
    if "template_category" in data:
        row.template_category = data["template_category"]
    if "target_sessions" in data and data["target_sessions"] is not None:
        row.target_sessions = data["target_sessions"]

    if row.is_active:
        onboarding = data.get("onboarding_completed")
        _sync_legacy_user_plan(
            user,
            row,
            db,
            onboarding=onboarding if onboarding is not None else None,
        )

    db.commit()
    db.refresh(row)
    return _plan_out(row, db)


@router.post("/{plan_id}/activate", response_model=WorkoutPlanOut)
def activate_plan(
    plan_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    if row.completed_at is not None:
        raise HTTPException(status_code=400, detail="Cannot activate a completed plan")

    _deactivate_all(user.id, db)
    row.is_active = 1
    _sync_legacy_user_plan(user, row, db)
    db.commit()
    db.refresh(row)
    return _plan_out(row, db)


@router.post("/{plan_id}/analyze-body")
def analyze_plan_body(
    plan_id: int,
    lang: str = Query(default="en"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Run before/after body analysis and persist scores on the plan (without completing it)."""
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")

    before_b64 = (row.before_photo_base64 or "").strip()
    after_b64 = (row.after_photo_base64 or "").strip()
    if not before_b64 or not after_b64:
        raise HTTPException(
            status_code=400,
            detail="Both before and after photos are required on this plan.",
        )

    language = "ar" if (lang or "").strip().lower().startswith("ar") else "en"
    analysis_category = (
        (row.template_category or "").strip()
        or (row.name if row.plan_kind == "template" else "")
        or "Muscle Gain"
    )

    try:
        mod = _load_analyzer()
        before_clean = mod.strip_data_url(before_b64)
        after_clean = mod.strip_data_url(after_b64)
        result = mod.compare_before_after(
            before_clean,
            after_clean,
            analysis_category,
            language,
            template_category=row.template_category,
        )
        analysis_dict = result.to_api_dict(language)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="Body analysis unavailable. Try again later.",
        ) from exc

    row.analysis_json = json.dumps(analysis_dict)
    row.ai_overall_score = float(result.overall_score)
    row.ai_alignment_percent = float(result.plan_alignment_percent)
    if user.plan and after_b64:
        user.plan.after_photo_base64 = after_b64
    db.commit()
    db.refresh(row)
    return analysis_dict


@router.post("/{plan_id}/complete", response_model=PlanCompletionOut)
def complete_plan(
    plan_id: int,
    body: PlanCompleteRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    if row.completed_at is not None:
        raise HTTPException(status_code=400, detail="Plan already completed")

    after_b64 = (body.after_photo_base64 or "").strip()
    if not after_b64:
        raise HTTPException(status_code=400, detail="After photo is required")

    before_b64 = (row.before_photo_base64 or "").strip()
    if not before_b64:
        raise HTTPException(status_code=400, detail="Before photo missing on this plan")

    stats = _aggregate_stats(db, row.id)
    target = _effective_target(row)
    completion_pct = min(100.0, (stats.total_sessions / target) * 100.0) if target else 100.0

    analysis_dict: dict | None = None
    ai_overall: float | None = None
    ai_alignment: float | None = None

    lang = (body.language_code or "en").strip().lower()
    lang = "ar" if lang.startswith("ar") else "en"

    try:
        mod = _load_analyzer()
        analysis_category = (
            (row.template_category or "").strip()
            or (row.name if row.plan_kind == "template" else "")
            or "Muscle Gain"
        )
        result = mod.compare_before_after(
            before_b64=before_b64,
            after_b64=after_b64,
            category=analysis_category,
            lang=lang,
            template_category=row.template_category,
        )
        analysis_dict = result.to_api_dict(lang=lang)
        ai_overall = float(result.overall_score)
        ai_alignment = float(result.plan_alignment_percent)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail="Body analysis unavailable. Try again later.",
        ) from exc

    stats_dict = stats.model_dump()
    row.after_photo_base64 = after_b64
    row.completed_at = datetime.now(timezone.utc)
    row.completion_percent = round(completion_pct, 1)
    row.ai_overall_score = ai_overall
    row.ai_alignment_percent = ai_alignment
    row.stats_json = json.dumps(stats_dict)
    row.analysis_json = json.dumps(analysis_dict) if analysis_dict else None
    row.is_active = 0

    if user.plan:
        user.plan.after_photo_base64 = after_b64

    db.commit()
    db.refresh(row)

    return PlanCompletionOut(
        plan=_plan_out(row, db),
        stats=stats,
        analysis=analysis_dict,
    )


@router.get("/{plan_id}/completion", response_model=PlanCompletionOut)
def get_plan_completion(
    plan_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")
    if row.completed_at is None:
        raise HTTPException(status_code=400, detail="Plan is not completed yet")

    stats: PlanCompletionStatsOut
    if row.stats_json:
        try:
            stats = PlanCompletionStatsOut.model_validate(json.loads(row.stats_json))
        except Exception:
            stats = _aggregate_stats(db, row.id)
    else:
        stats = _aggregate_stats(db, row.id)

    analysis: dict | None = None
    if row.analysis_json:
        try:
            analysis = json.loads(row.analysis_json)
        except json.JSONDecodeError:
            analysis = None

    return PlanCompletionOut(plan=_plan_out(row, db), stats=stats, analysis=analysis)


@router.delete("/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_plan(
    plan_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    row = db.scalar(
        select(WorkoutPlan).where(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id)
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Plan not found")

    was_active = bool(row.is_active)
    db.delete(row)
    db.flush()

    if was_active:
        nxt = db.scalar(
            select(WorkoutPlan)
            .where(WorkoutPlan.user_id == user.id, WorkoutPlan.completed_at.is_(None))
            .order_by(WorkoutPlan.created_at.desc())
        )
        if nxt:
            nxt.is_active = 1
            _sync_legacy_user_plan(user, nxt, db)
        elif user.plan:
            user.plan.onboarding_completed = 0

    db.commit()
    return None
