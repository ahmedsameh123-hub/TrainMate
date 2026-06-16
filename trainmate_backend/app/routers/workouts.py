import re

from fastapi import APIRouter, Depends
from groq import Groq
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User, WorkoutPlan, WorkoutSession
from app.schemas import WorkoutCreate, WorkoutOut

router = APIRouter(prefix="/workouts", tags=["workouts"])


def _met_for_label(label: str) -> float:
    l = label.lower()
    if "push" in l or "pushup" in l or "push-up" in l:
        return 3.8
    if "squat" in l:
        return 5.0
    if "curl" in l or "bicep" in l:
        return 3.5
    if "deadlift" in l or "dead" in l:
        return 6.0
    if "bench" in l or "press" in l or "shoulder" in l:
        return 4.0
    return 4.0


def _resolve_kcal(body: WorkoutCreate, user: User, exercise_label: str) -> float | None:
    if body.estimated_kcal is not None:
        return round(float(body.estimated_kcal), 2)
    w = body.weight_kg
    if w is None and user.profile is not None:
        w = user.profile.weight_kg
    if w is None or body.duration_sec is None:
        return None
    met = _met_for_label(exercise_label)
    return round(met * float(w) * (body.duration_sec / 3600.0), 2)


def _workout_row_to_out(row: WorkoutSession) -> WorkoutOut:
    return WorkoutOut(
        id=row.id,
        exercise_label=row.exercise_label,
        reps=row.reps,
        duration_sec=row.duration_sec,
        source=row.source,
        created_at=row.created_at.isoformat() if row.created_at else "",
        weight_kg=row.weight_kg,
        equipment=row.equipment,
        sets=row.sets,
        estimated_kcal=row.estimated_kcal,
        session_report=row.session_report,
    )


def _normalize_lang(language_code: str | None) -> str:
    lang = (language_code or "en").strip().lower()
    return "ar" if lang.startswith("ar") else "en"


def _clean_report_text(text: str) -> str:
    cleaned = text.replace("\r", "")
    cleaned = re.sub(r"[#*•]+", "", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def _offline_session_report_en(
    *,
    exercise_label: str,
    reps: int,
    duration_sec: int | None,
    weight_kg: float | None,
    equipment: str | None,
    sets: int | None,
    kcal: float | None,
    plan_category: str | None,
) -> str:
    dur = f"{duration_sec // 60} min {duration_sec % 60} sec" if duration_sec else "Not specified"
    load = f"{weight_kg} kg" if weight_kg is not None else "Bodyweight / not specified"
    eq = equipment or "Not specified"
    st = f"{sets} sets" if sets else "Not specified"
    k = f"{kcal:.0f} kcal estimated" if kcal is not None else "Calorie estimate unavailable"
    cat = plan_category or "general fitness"
    return (
        f"Session summary\n"
        f"Exercise: {exercise_label}\n"
        f"Reps: {reps}\n"
        f"Duration: {dur}\n"
        f"Load: {load} ({eq})\n"
        f"Sets: {st}\n"
        f"Calories: {k}\n\n"
        f"Performance notes\n"
        f"Keep your core stable and breathing steady. Add reps, control, or time under tension gradually.\n\n"
        f"Next-step suggestion\n"
        f"Stay consistent with 3 to 4 sessions this week and progress in a way that matches your goal: {cat}.\n\n"
        f"Nutrition note\n"
        f"Center meals around protein, water, fruit, and vegetables to support recovery."
    )


def _offline_session_report_ar(
    *,
    exercise_label: str,
    reps: int,
    duration_sec: int | None,
    weight_kg: float | None,
    equipment: str | None,
    sets: int | None,
    kcal: float | None,
    plan_category: str | None,
) -> str:
    dur = f"{duration_sec // 60} دقيقة و {duration_sec % 60} ثانية" if duration_sec else "غير محدد"
    load = f"{weight_kg} كجم" if weight_kg is not None else "وزن الجسم / غير محدد"
    eq = equipment or "غير محدد"
    st = f"{sets} جولات" if sets else "غير محدد"
    k = f"{kcal:.0f} سعرة تقريبية" if kcal is not None else "تقدير السعرات غير متاح (أضف وزن الجسم في الملف الشخصي أو أدخل الحمل)"
    cat = plan_category or "عام"
    return (
        f"ملخص الجلسة\n"
        f"التمرين: {exercise_label}\n"
        f"التكرارات: {reps}\n"
        f"مدة الجلسة: {dur}\n"
        f"الحمل: {load} ({eq})\n"
        f"الجولات المذكورة: {st}\n"
        f"حرق تقريبي: {k}\n\n"
        f"أداء وتقنية\n"
        f"ثبّت الجذع والتنفس بشكل منتظم، وزِد التكرار أو الوقت تحت الشدة تدريجياً.\n\n"
        f"الخطوة التالية\n"
        f"حافظ على 3 إلى 4 جلسات هذا الأسبوع وتقدم بما يناسب هدفك: {cat}.\n\n"
        f"تغذية عامة\n"
        f"اجعل وجباتك فيها بروتين وماء وخضار وفاكهة لدعم الاستشفاء."
    )


def _ai_session_report(
    *,
    user: User,
    exercise_label: str,
    reps: int,
    duration_sec: int | None,
    weight_kg: float | None,
    equipment: str | None,
    sets: int | None,
    kcal: float | None,
    language_code: str | None,
) -> str:
    p = user.profile
    plan = user.plan
    lang = _normalize_lang(language_code)
    prof = (
        f"age={p.age}, sex={p.sex}, height_cm={p.height_cm}, weight_kg={p.weight_kg}"
        if p
        else "unknown"
    )
    pl = (
        f"category={plan.category}, weeks={plan.duration_weeks}"
        if plan
        else "unknown"
    )
    payload = (
        "Write a workout session report for this user.\n"
        f"Language: {'Arabic' if lang == 'ar' else 'English'}.\n"
        "Output must be plain text only. Do not use markdown, hashtags, bullets, or stars.\n"
        "Keep it short, natural, practical, and easy to scan.\n"
        f"Include exercise={exercise_label}, reps={reps}, duration_sec={duration_sec}, "
        f"weight_kg={weight_kg}, equipment={equipment}, sets={sets}, estimated_kcal={kcal}.\n"
        "Cover: summary, performance note, next step, and one simple nutrition tip.\n"
        f"User profile: {prof}. Plan: {pl}.\n"
        "No medical diagnosis."
    )
    if not settings.groq_api_key:
        fallback = _offline_session_report_ar if lang == "ar" else _offline_session_report_en
        return fallback(
            exercise_label=exercise_label,
            reps=reps,
            duration_sec=duration_sec,
            weight_kg=weight_kg,
            equipment=equipment,
            sets=sets,
            kcal=kcal,
            plan_category=plan.category if plan else None,
        )
    try:
        client = Groq(api_key=settings.groq_api_key)
        resp = client.chat.completions.create(
            model=settings.groq_model,
            messages=[
                {
                    "role": "system",
                    "content": (
                        "You are an expert fitness and nutrition coach. "
                        f"Reply only in {'Arabic' if lang == 'ar' else 'English'}. "
                        "Use plain text only with no markdown or hashtags."
                    ),
                },
                {"role": "user", "content": payload},
            ],
            temperature=0.35,
        )
        text = _clean_report_text((resp.choices[0].message.content or "").strip())
        if text:
            return text
    except Exception:
        pass
    fallback = _offline_session_report_ar if lang == "ar" else _offline_session_report_en
    return fallback(
        exercise_label=exercise_label,
        reps=reps,
        duration_sec=duration_sec,
        weight_kg=weight_kg,
        equipment=equipment,
        sets=sets,
        kcal=kcal,
        plan_category=plan.category if plan else None,
    )


@router.post("", response_model=WorkoutOut, status_code=201)
def create_workout(
    body: WorkoutCreate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    label = body.exercise_label.strip()
    kcal = _resolve_kcal(body, user, label)

    active_plan = db.scalar(
        select(WorkoutPlan).where(
            WorkoutPlan.user_id == user.id,
            WorkoutPlan.is_active == 1,
            WorkoutPlan.completed_at.is_(None),
        )
    )
    plan_id = active_plan.id if active_plan else None

    row = WorkoutSession(
        user_id=user.id,
        plan_id=plan_id,
        exercise_label=label,
        reps=body.reps,
        duration_sec=body.duration_sec,
        source=body.source,
        weight_kg=body.weight_kg,
        equipment=body.equipment,
        sets=body.sets,
        estimated_kcal=kcal,
        session_report=None,
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    if body.generate_ai_report:
        report = _ai_session_report(
            user=user,
            exercise_label=label,
            reps=body.reps,
            duration_sec=body.duration_sec,
            weight_kg=body.weight_kg,
            equipment=body.equipment,
            sets=body.sets,
            kcal=kcal,
            language_code=body.language_code,
        )
        row.session_report = report
        db.commit()
        db.refresh(row)

    return _workout_row_to_out(row)


@router.get("", response_model=list[WorkoutOut])
def list_workouts(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    limit: int = 50,
):
    limit = min(max(limit, 1), 200)
    rows = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user.id)
        .order_by(WorkoutSession.created_at.desc())
        .limit(limit)
    ).all()
    return [_workout_row_to_out(r) for r in rows]
