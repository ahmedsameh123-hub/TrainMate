from fastapi import APIRouter, Depends, Query
from groq import Groq
import importlib
import json
from collections import Counter
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.deps import get_current_user
from app.models import User, WorkoutPlan, WorkoutSession
from app.schemas import ChatRequest, ChatResponse

router = APIRouter(prefix="/chat", tags=["chat"])

SYSTEM_PROMPT = (
    "You are a helpful assistant. "
    "Reply naturally and clearly. "
    "Use plain text and keep the style natural. "
    "When the user asks about their training history, reference the provided user context precisely."
)


def _recent_workouts_summary(db: Session, user_id: int, limit: int = 14) -> str:
    rows = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id)
        .order_by(WorkoutSession.created_at.desc())
        .limit(limit)
    ).all()
    if not rows:
        return "no logged workouts yet"
    chunks: list[str] = []
    for w in rows:
        bits = [w.exercise_label, f"reps={w.reps}"]
        if w.duration_sec is not None:
            bits.append(f"sec={w.duration_sec}")
        if w.weight_kg is not None:
            bits.append(f"load_kg={w.weight_kg}")
        if w.equipment:
            bits.append(f"eq={w.equipment}")
        if w.sets is not None:
            bits.append(f"sets={w.sets}")
        if w.estimated_kcal is not None:
            bits.append(f"kcal~{w.estimated_kcal:.0f}")
        chunks.append("(" + ", ".join(bits) + ")")
    return " | ".join(chunks)


def _last_session_report_excerpt(db: Session, user_id: int, max_chars: int = 1200) -> str:
    row = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id, WorkoutSession.session_report.isnot(None))
        .order_by(WorkoutSession.created_at.desc())
        .limit(1)
    ).first()
    if not row or not (row.session_report or "").strip():
        return "none"
    t = row.session_report.strip()
    if len(t) > max_chars:
        return t[:max_chars] + "…"
    return t


def _recent_workouts_detailed(db: Session, user_id: int, limit: int = 40) -> str:
    rows = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id)
        .order_by(WorkoutSession.created_at.desc())
        .limit(limit)
    ).all()
    if not rows:
        return "none"

    lines: list[str] = []
    for i, w in enumerate(rows, start=1):
        report_text = (w.session_report or "").strip()
        report_short = report_text[:280] + "…" if len(report_text) > 280 else (report_text or "none")
        lines.append(
            (
                f"{i}) date={w.created_at}, exercise={w.exercise_label}, reps={w.reps}, "
                f"duration_sec={w.duration_sec}, weight_kg={w.weight_kg}, equipment={w.equipment}, "
                f"sets={w.sets}, estimated_kcal={w.estimated_kcal}, source={w.source}, "
                f"session_report={report_short}"
            )
        )
    return "\n".join(lines)


def _workout_stats_block(db: Session, user_id: int) -> str:
    rows = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user_id)
        .order_by(WorkoutSession.created_at.desc())
        .limit(200)
    ).all()
    if not rows:
        return "no workout stats yet"

    total_sessions = len(rows)
    total_reps = sum(int(w.reps or 0) for w in rows)
    total_duration = sum(int(w.duration_sec or 0) for w in rows)
    total_kcal = sum(float(w.estimated_kcal or 0.0) for w in rows)

    last7 = rows[:7]
    last30 = rows[:30]
    reps_last7 = sum(int(w.reps or 0) for w in last7)
    reps_last30 = sum(int(w.reps or 0) for w in last30)

    by_ex = Counter((w.exercise_label or "").strip().lower() for w in rows if (w.exercise_label or "").strip())
    top_exercise = by_ex.most_common(1)[0][0] if by_ex else "none"
    last = rows[0]
    return (
        f"sessions_total={total_sessions}, reps_total={total_reps}, "
        f"duration_total_sec={total_duration}, kcal_total~{total_kcal:.0f}, "
        f"reps_last_7_sessions={reps_last7}, reps_last_30_sessions={reps_last30}, "
        f"top_exercise={top_exercise}, "
        f"last_session=(exercise={last.exercise_label}, reps={last.reps}, duration_sec={last.duration_sec}, "
        f"weight_kg={last.weight_kg}, sets={last.sets}, kcal={last.estimated_kcal}, source={last.source})"
    )


def _user_context(db: Session, user: User) -> str:
    p = user.profile
    plan = user.plan
    wp = db.scalar(
        select(WorkoutPlan).where(
            WorkoutPlan.user_id == user.id,
            WorkoutPlan.is_active == 1,
            WorkoutPlan.completed_at.is_(None),
        )
    )
    identity_line = (
        f"id={user.id}, name={user.name}, email={user.email}, phone={user.phone}, "
        f"email_verified={user.email_verified}, pending_email={user.pending_email}"
    )
    profile_line = (
        f"age={p.age}, sex={p.sex}, height_cm={p.height_cm}, weight_kg={p.weight_kg}, notes={p.notes}"
        if p
        else "unknown"
    )
    plan_line = (
        f"category={plan.category}, duration_weeks={plan.duration_weeks}, "
        f"onboarding_completed={bool(plan.onboarding_completed)}, "
        f"has_before_photo={bool(plan.before_photo_base64)}, has_after_photo={bool(plan.after_photo_base64)}"
        if plan
        else "unknown"
    )
    wp_line = "none"
    if wp:
        wp_line = (
            f"name={wp.name}, template_category={wp.template_category}, "
            f"duration_weeks={wp.duration_weeks}, "
            f"has_before_photo={bool(wp.before_photo_base64)}, "
            f"has_after_photo={bool(wp.after_photo_base64)}, "
            f"analysis_saved={bool(wp.analysis_json)}, "
            f"ai_overall_score={wp.ai_overall_score}, "
            f"ai_alignment_percent={wp.ai_alignment_percent}"
        )
    wo = _recent_workouts_summary(db, user.id)
    wo_detail = _recent_workouts_detailed(db, user.id)
    wo_stats = _workout_stats_block(db, user.id)
    rep = _last_session_report_excerpt(db, user.id)
    return (
        "Authenticated user context — use all of this to personalize answers. "
        "Prefer these facts over assumptions. If a value is missing, say it is missing.\n"
        f"- Identity: {identity_line}\n"
        f"- Profile: {profile_line}\n"
        f"- Legacy onboarding plan: {plan_line}\n"
        f"- Active workout plan: {wp_line}\n"
        f"- Workout stats: {wo_stats}\n"
        f"- Recent workouts summary (newest first): {wo}\n"
        f"- Recent workouts detailed (newest first):\n{wo_detail}\n"
        f"- Latest saved session report excerpt: {rep}"
    )


def _load_body_analyzer():
    from app.routers.body_progress import _load_analyzer

    return _load_analyzer()


def _plan_with_progress_photos(db: Session, user_id: int) -> WorkoutPlan | None:
    wp = db.scalar(
        select(WorkoutPlan).where(
            WorkoutPlan.user_id == user_id,
            WorkoutPlan.is_active == 1,
            WorkoutPlan.completed_at.is_(None),
        )
    )
    if wp and wp.before_photo_base64 and wp.after_photo_base64:
        return wp
    return db.scalar(
        select(WorkoutPlan)
        .where(
            WorkoutPlan.user_id == user_id,
            WorkoutPlan.before_photo_base64.isnot(None),
            WorkoutPlan.after_photo_base64.isnot(None),
        )
        .order_by(WorkoutPlan.is_active.desc(), WorkoutPlan.id.desc())
    )


def _progress_keywords(text: str) -> bool:
    t = (text or "").lower()
    en = (
        "progress",
        "before",
        "after",
        "photo",
        "body",
        "muscle",
        "weight",
        "physique",
        "transformation",
        "compare",
        "gain",
        "loss",
    )
    ar = ("تقدم", "قبل", "بعد", "صور", "صورة", "جسم", "عض", "وزن", "تحول", "مقار")
    return any(k in t for k in en) or any(k in (text or "") for k in ar)


def _body_progress_context(
    db: Session, user: User, lang: str = "en"
) -> tuple[str, str | None, str | None]:
    """Return narrative context plus optional before/after base64 for vision."""
    wp = _plan_with_progress_photos(db, user.id)
    if wp is None:
        return "No workout plan with before/after progress photos on this account.", None, None

    before = (wp.before_photo_base64 or "").strip()
    after = (wp.after_photo_base64 or "").strip()
    if not before or not after:
        return "Progress photos are incomplete on the active plan.", None, None

    is_ar = lang.lower().startswith("ar")
    category = (wp.template_category or wp.name or "Muscle Gain").strip()
    lines = [
        (
            f"خطة التقدم: {wp.name} ({category})، المدة {wp.duration_weeks} أسابيع. "
            f"صورة قبل موجودة: نعم. صورة بعد موجودة: نعم."
            if is_ar
            else (
                f"Progress plan: {wp.name} ({category}), {wp.duration_weeks} weeks. "
                "Before photo: yes. After photo: yes."
            )
        )
    ]

    analysis_dict: dict | None = None
    if wp.analysis_json:
        try:
            analysis_dict = json.loads(wp.analysis_json)
        except json.JSONDecodeError:
            analysis_dict = None

    if analysis_dict is None:
        try:
            mod = _load_body_analyzer()
            before_clean = mod.strip_data_url(before)
            after_clean = mod.strip_data_url(after)
            result = mod.compare_before_after(
                before_clean,
                after_clean,
                category,
                lang,
                template_category=wp.template_category,
            )
            analysis_dict = result.to_api_dict(lang)
            wp.analysis_json = json.dumps(analysis_dict)
            wp.ai_overall_score = float(analysis_dict.get("overallScore", 0))
            wp.ai_alignment_percent = float(analysis_dict.get("planAlignmentPercent", 0))
            db.commit()
        except ValueError as exc:
            lines.append(
                f"تعذّر تحليل الصور: {exc}" if is_ar else f"Could not analyze photos: {exc}"
            )
            return "\n".join(lines), before, after
        except Exception as exc:
            lines.append(
                f"تحليل التقدم غير متاح حالياً: {exc}"
                if is_ar
                else f"Progress analysis unavailable: {exc}"
            )
            return "\n".join(lines), before, after

    if analysis_dict:
        summary = analysis_dict.get("summary") or ""
        overall = analysis_dict.get("overallScore")
        aligned = analysis_dict.get("planAligned")
        regions = analysis_dict.get("regions") or []
        region_bits = []
        for r in regions[:8]:
            region_bits.append(
                f"{r.get('label')}: {r.get('status')} "
                f"({r.get('changePercent', 0):+.1f}%, score={r.get('score')})"
            )
        lines.append(
            f"Overall progress score: {overall}/100. Plan aligned with goals: {aligned}. "
            f"Summary: {summary}"
        )
        if region_bits:
            lines.append("Regional breakdown: " + "; ".join(region_bits))
        narrative = analysis_dict.get("narrative")
        if narrative:
            lines.append(f"Coach narrative: {narrative}")

    lines.append(
        "When answering about body progress, use ONLY these measured values. "
        "Do not invent muscle changes that are not supported by the analysis."
    )
    return "\n".join(lines), before, after


def _last_user_text(body: ChatRequest) -> str:
    if body.message and body.message.strip():
        return body.message.strip()
    for m in reversed(body.messages):
        if m.role == "user" and m.content.strip():
            return m.content.strip()
    return ""


def _looks_arabic(text: str) -> bool:
    return any("\u0600" <= ch <= "\u06FF" for ch in text)


def _language_mode(text: str) -> str:
    ar = sum(1 for ch in text if "\u0600" <= ch <= "\u06FF")
    en = sum(1 for ch in text if ("a" <= ch.lower() <= "z"))
    if ar == 0 and en == 0:
        return "en"
    if ar > 0 and en > 0:
        if ar >= en * 1.2:
            return "ar"
        if en >= ar * 1.2:
            return "en"
        return "mixed"
    return "ar" if ar > 0 else "en"


def _language_instruction(text: str) -> str:
    mode = _language_mode(text)
    if mode == "ar":
        return "Respond fully in Arabic."
    if mode == "en":
        return "Respond fully in English."
    return (
        "The user wrote in mixed Arabic and English. "
        "Reply in the same mixed style naturally: keep Arabic parts in Arabic and English terms in English."
    )


def _supports_vision(model_name: str) -> bool:
    m = (model_name or "").lower()
    return any(
        k in m
        for k in (
            "vision",
            "llava",
            "gpt-4o",
            "gpt-4.1",
            "gemini",
            "claude-3",
            "pixtral",
            "qwen-vl",
            "qwen2-vl",
        )
    )


def _pick_provider() -> str:
    p = (settings.llm_provider or "auto").strip().lower()
    if p in {"groq", "openrouter"}:
        return p
    if (settings.openrouter_api_key or "").strip():
        return "openrouter"
    return "groq"


def _provider_ready(provider: str) -> bool:
    if provider == "openrouter":
        return bool((settings.openrouter_api_key or "").strip())
    return bool((settings.groq_api_key or "").strip())


def _provider_model(provider: str) -> str:
    if provider == "openrouter":
        return (settings.openrouter_model or "").strip() or "openai/gpt-4o-mini"
    return (settings.groq_model or "").strip() or "llama-3.1-8b-instant"


def _chat_completion(provider: str, messages: list[dict[str, object]]) -> str:
    if provider == "openrouter":
        openai_mod = importlib.import_module("openai")
        openai_client_cls = getattr(openai_mod, "OpenAI")
        client = openai_client_cls(
            api_key=settings.openrouter_api_key.strip(),
            base_url=(settings.openrouter_base_url or "").strip()
            or "https://openrouter.ai/api/v1",
        )
        resp = client.chat.completions.create(
            model=_provider_model(provider),
            messages=messages,  # type: ignore[arg-type]
            temperature=0.3,
        )
        return (resp.choices[0].message.content or "").strip()

    client = Groq(api_key=settings.groq_api_key.strip())
    resp = client.chat.completions.create(
        model=_provider_model(provider),
        messages=messages,  # type: ignore[arg-type]
        temperature=0.3,
    )
    return (resp.choices[0].message.content or "").strip()


def _is_greeting(text: str) -> bool:
    t = text.strip().lower()
    raw = text.strip()
    en = {"hi", "hey", "hello", "hallo", "yo", "sup", "howdy", "greetings", "gm", "gn"}
    tokens = {x.strip(".,!?;") for x in t.replace(",", " ").split() if x}
    if tokens & en:
        return True
    if t in en or any(t.startswith(p + " ") for p in ("hi", "hey", "hello")):
        return True
    ar = ("مرحب", "أهلا", "اهلا", "هلا", "السلام", "صباح", "مساء", "هاي", "هلو")
    return any(k in raw for k in ar)


def _is_thanks(text: str) -> bool:
    t = text.strip().lower()
    if any(x in t for x in ("thank", "thanks", "thx", "شكر", "ممنون", "تسلم")):
        return True
    return False


def _offline_coach_reply(user_text: str) -> str:
    raw = (user_text or "").strip()
    mode = _language_mode(raw)
    if not raw:
        return (
            "مرحبًا، أنا مساعدك الذكي. ابعت سؤالك وأنا معاك."
            if mode != "en"
            else "Hello, I am your AI assistant. Ask me anything."
        )
    if mode == "ar":
        return "الخدمة غير متاحة مؤقتًا. حاول مرة كمان بعد ثواني."
    if mode == "mixed":
        return "الخدمة offline دلوقتي. جرّب تاني بعد شوية."
    return "The service is temporarily offline. Please try again in a moment."


def _clean_reply_text(text: str) -> str:
    t = (text or "").strip()
    if not t:
        return t
    # Keep output plain and easy to read.
    t = t.replace("**", "").replace("*", "")
    t = t.replace("#", "")
    t = t.replace("•", "-")
    return t


def _build_user_content(body: ChatRequest) -> tuple[object | None, bool]:
    has_image = bool((body.image_base64 or "").strip())
    can_use_image = has_image and _supports_vision(_provider_model(_pick_provider()))
    msg = (body.message or "").strip()

    if can_use_image:
        parts: list[dict[str, object]] = []
        if msg:
            parts.append({"type": "text", "text": msg})
        parts.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{body.image_base64.strip()}"},
            }
        )
        return parts, has_image

    if msg:
        return msg, has_image

    return None, has_image


@router.post("", response_model=ChatResponse)
def chat(
    body: ChatRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    last = _last_user_text(body)
    user_content, has_image = _build_user_content(body)
    prefers_ar = _looks_arabic(last)
    offline_image_reply = (
        "استلمت الصورة. أقدر أساعدك أفضل لو وصفت سؤالك باختصار (مثلاً: ألم ركبة أثناء السكوات أو تقييم وضعية الضغط)."
        if prefers_ar
        else "I received your image. I can help better if you add a short prompt (for example: knee pain during squats or push-up form review)."
    )

    provider = _pick_provider()
    if not _provider_ready(provider):
        if has_image:
            return ChatResponse(reply=offline_image_reply)
        return ChatResponse(reply=_offline_coach_reply(last))

    try:
        user_ctx = _user_context(db, user)
    except Exception:
        user_ctx = "Authenticated user context unavailable."

    lang = "ar" if prefers_ar else "en"
    body_ctx, progress_before, progress_after = _body_progress_context(db, user, lang)

    groq_messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "system", "content": user_ctx},
        {"role": "system", "content": body_ctx},
        {
            "role": "system",
            "content": (
                "Personalization rules: "
                "1) Use the authenticated user identity (name/email/plan/profile/workouts) whenever relevant. "
                "2) Do not invent personal details. "
                "3) If user asks about progress, cite exact numbers from workout stats and body-progress analysis when available. "
                "4) Keep answers concise and practical."
            ),
        },
        {"role": "system", "content": _language_instruction(last)},
    ]

    progress_vision = (
        progress_before
        and progress_after
        and _progress_keywords(last)
        and _provider_ready("openrouter")
        and _supports_vision(_provider_model("openrouter"))
    )
    if progress_vision:
        vision_prompt = (
            "These are the user's BEFORE and AFTER progress photos. "
            "Describe only what is visible and align with the numeric analysis already provided."
            if not prefers_ar
            else "هذه صور قبل/بعد للمستخدم. صف فقط ما هو ظاهر واربطه بالتحليل الرقمي المرفق."
        )
        groq_messages.append(
            {
                "role": "system",
                "content": [
                    {"type": "text", "text": vision_prompt},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{progress_before}"},
                    },
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{progress_after}"},
                    },
                ],
            }
        )
    other_ctx = (body.cross_chat_summary or "").strip()
    if other_ctx:
        groq_messages.append(
            {
                "role": "system",
                "content": (
                    "Additional memory: the user has other saved chats in this app. "
                    "Excerpts from those conversations appear below (may be truncated). "
                    "Treat them as background context across threads; prioritize the CURRENT "
                    "messages and merge facts naturally without repeating verbatim.\n\n"
                    + other_ctx[:19000]
                ),
            },
        )
    for m in body.messages:
        groq_messages.append({"role": m.role, "content": m.content})
    if user_content is not None:
        groq_messages.append({"role": "user", "content": user_content})

    # Need at least one user message for the LLM (two system prompts alone are not enough).
    user_roles = {"user", "assistant"}
    if not any(m.get("role") in user_roles for m in groq_messages[2:]):
        if has_image and user_content is None:
            return ChatResponse(
                reply=(
                    "الموديل الحالي لا يدعم تحليل الصور. اكتب سؤالك كنص وسأجيبك فورًا."
                    if prefers_ar
                    else "The current model does not support image analysis. Send your question as text and I will answer right away."
                )
            )
        return ChatResponse(reply=_offline_coach_reply(last))

    try:
        reply = _chat_completion(provider, groq_messages)
        if reply:
            return ChatResponse(reply=_clean_reply_text(reply))
    except Exception:
        # Keep the app responsive with a practical fallback reply.
        pass

    # Groq unavailable, bad key, or empty reply — always return a usable coach message (no 5xx).
    if has_image:
        return ChatResponse(reply=offline_image_reply)
    return ChatResponse(reply=_offline_coach_reply(last))


@router.post("/progress-feedback", response_model=ChatResponse)
def progress_feedback(
    lang: str = Query(default="en"),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    workouts = db.scalars(
        select(WorkoutSession)
        .where(WorkoutSession.user_id == user.id)
        .order_by(WorkoutSession.created_at.desc())
        .limit(60)
    ).all()
    total_sessions = len(workouts)
    total_reps = sum(w.reps for w in workouts)
    plan = user.plan
    p = user.profile
    provider = _pick_provider()
    is_ar = (lang or "").strip().lower().startswith("ar")
    if not _provider_ready(provider):
        before_ok = bool(plan and plan.before_photo_base64)
        after_ok = bool(plan and plan.after_photo_base64)
        if total_sessions == 0:
            msg = (
                "ابدأ أول تمرين اليوم عشان نقدر نتابع تقدمك."
                if is_ar
                else "Start your first workout today so we can track your progress."
            )
        elif total_sessions < 6:
            msg = (
                "بداية جيدة. حاول 3-4 جلسات أسبوعيًا مع التدرج."
                if is_ar
                else "Good start. Try 3-4 sessions per week with gradual progression."
            )
        else:
            msg = (
                "ممتاز. استمر على نفس المعدل مع راحة كافية وتغذية كويسة."
                if is_ar
                else "Great. Keep the same pace with enough rest and good nutrition."
            )
        if before_ok and after_ok:
            msg += (
                " تم رفع صور قبل/بعد، راقب القياسات والقوة أسبوعيًا."
                if is_ar
                else " Before/after photos are uploaded, track your measurements and strength weekly."
            )
        return ChatResponse(reply=_clean_reply_text(msg))

    wo_summary = _recent_workouts_summary(db, user.id, limit=10)
    rep_excerpt = _last_session_report_excerpt(db, user.id, max_chars=800)
    prompt = (
        f"Give concise progress feedback to this user in {'Arabic' if is_ar else 'English'} with 4 short points: "
        "current level, improvements, weaknesses, next 7-day plan. "
        f"profile age={p.age if p else None}, height={p.height_cm if p else None}, weight={p.weight_kg if p else None}; "
        f"plan category={plan.category if plan else None}, duration_weeks={plan.duration_weeks if plan else None}, "
        f"before_photo={'yes' if plan and plan.before_photo_base64 else 'no'}, after_photo={'yes' if plan and plan.after_photo_base64 else 'no'}; "
        f"workouts sessions={total_sessions}, reps={total_reps}. "
        f"Recent detail: {wo_summary}. Latest report excerpt: {rep_excerpt}"
    )
    try:
        reply = _chat_completion(
            provider,
            [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
        )
        return ChatResponse(reply=_clean_reply_text(reply))
    except Exception:
        return ChatResponse(
            reply=_clean_reply_text(
                (
                "مستواك جيد، استمر 4 جلسات الأسبوع القادم مع رفع شدة بسيط."
                if is_ar
                else "Your level is good. Keep 4 sessions next week with a slight increase in intensity."
                )
            )
        )
