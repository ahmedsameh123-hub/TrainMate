import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.config import settings

_log = logging.getLogger("uvicorn.error")
from app.database import Base, engine, SessionLocal
from app.routers import auth, body_progress, chat, ml, plans, users, workouts
from app.plan_migration import migrate_legacy_plans

API_VERSION = "1.0.0"
BUILD_ID = "trainmate-backend-1"


def _ensure_sqlite_columns():
    if not settings.database_url.startswith("sqlite"):
        return
    with engine.begin() as conn:
        prof_cols = {r[1] for r in conn.execute(text("PRAGMA table_info(user_profiles)")).fetchall()}
        if "profile_image_base64" not in prof_cols:
            conn.execute(text("ALTER TABLE user_profiles ADD COLUMN profile_image_base64 TEXT"))

        plan_cols = {r[1] for r in conn.execute(text("PRAGMA table_info(user_plans)")).fetchall()}
        if "after_photo_base64" not in plan_cols:
            conn.execute(text("ALTER TABLE user_plans ADD COLUMN after_photo_base64 TEXT"))

        user_cols = {r[1] for r in conn.execute(text("PRAGMA table_info(users)")).fetchall()}
        if "phone" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN phone VARCHAR(32)"))
        if "email_verified" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN email_verified BOOLEAN NOT NULL DEFAULT 1"))
        if "pending_email" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN pending_email VARCHAR(255)"))
        if "verification_code_hash" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN verification_code_hash VARCHAR(128)"))
        if "verification_expires_at" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN verification_expires_at DATETIME"))
        if "verification_last_sent_at" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN verification_last_sent_at DATETIME"))
        if "password_reset_code_hash" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_reset_code_hash VARCHAR(128)"))
        if "password_reset_expires_at" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_reset_expires_at DATETIME"))
        if "password_reset_last_sent_at" not in user_cols:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_reset_last_sent_at DATETIME"))

        wo_cols = {r[1] for r in conn.execute(text("PRAGMA table_info(workout_sessions)")).fetchall()}
        if "weight_kg" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN weight_kg FLOAT"))
        if "equipment" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN equipment VARCHAR(32)"))
        if "sets" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN sets INTEGER"))
        if "estimated_kcal" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN estimated_kcal FLOAT"))
        if "session_report" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN session_report TEXT"))
        if "plan_id" not in wo_cols:
            conn.execute(text("ALTER TABLE workout_sessions ADD COLUMN plan_id INTEGER"))

        wp_cols = {r[1] for r in conn.execute(text("PRAGMA table_info(workout_plans)")).fetchall()}
        if "target_sessions" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN target_sessions INTEGER"))
        if "completed_at" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN completed_at DATETIME"))
        if "completion_percent" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN completion_percent FLOAT"))
        if "ai_overall_score" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN ai_overall_score FLOAT"))
        if "ai_alignment_percent" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN ai_alignment_percent FLOAT"))
        if "stats_json" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN stats_json TEXT"))
        if "analysis_json" not in wp_cols:
            conn.execute(text("ALTER TABLE workout_plans ADD COLUMN analysis_json TEXT"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    _ensure_sqlite_columns()
    with SessionLocal() as db:
        try:
            migrate_legacy_plans(db)
        except Exception as exc:
            _log.warning("Plan migration skipped: %s", exc)
    if not settings.email_delivery_ready:
        _log.warning(
            "Email delivery not configured — verification/reset codes will NOT reach the inbox. "
            "Set RESEND_API_KEY or SMTP_* in .env. See .env.example."
        )
    yield


app = FastAPI(title="TrainMate API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(users.router, prefix="/api")
app.include_router(plans.router, prefix="/api")
app.include_router(chat.router, prefix="/api")
app.include_router(workouts.router, prefix="/api")
app.include_router(ml.router, prefix="/api")
app.include_router(body_progress.router, prefix="/api")


@app.get("/api/health")
def health():
    pp_root = Path(__file__).resolve().parents[2]
    ai_models = pp_root / "ai" / "models"
    body_analyzer = pp_root / "ai" / "body_progress_analyzer.py"
    return {
        "status": "ok",
        "api_version": API_VERSION,
        "build": BUILD_ID,
        "groq_configured": bool(settings.groq_api_key),
        "smtp_configured": settings.smtp_ready,
        "resend_configured": settings.resend_ready,
        "email_delivery_configured": settings.email_delivery_ready,
        "email_delivery": (
            "resend"
            if settings.resend_ready
            else ("smtp" if settings.smtp_ready else "console_only")
        ),
        "expose_verification_codes": settings.expose_verification_codes,
        "ml_models_present": ai_models.is_dir()
        and (ai_models / "final_forthesis_bidirectionallstm_and_encoders_exercise_classifier_model.h5").is_file(),
        "body_analyzer_present": body_analyzer.is_file(),
    }
