import secrets
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.models import User
from app.security import hash_email_verification_code

_RESEND_COOLDOWN_SEC = 60
_CODE_TTL_MIN = 15
_PASSWORD_RESET_TTL_MIN = 15


def find_user_by_delivered_email(db: Session, em: str) -> User | None:
    return db.scalar(select(User).where(or_(User.email == em, User.pending_email == em)))


def enforce_resend_cooldown(user: User) -> None:
    if user.verification_last_sent_at is None:
        return
    last = user.verification_last_sent_at
    if last.tzinfo is None:
        last = last.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - last
    if delta.total_seconds() < _RESEND_COOLDOWN_SEC:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Please wait before requesting another code",
        )


def issue_verification_code(user: User, db: Session) -> str:
    raw = f"{secrets.randbelow(900000) + 100000:06d}"
    user.verification_code_hash = hash_email_verification_code(raw)
    user.verification_expires_at = datetime.now(timezone.utc) + timedelta(minutes=_CODE_TTL_MIN)
    user.verification_last_sent_at = datetime.now(timezone.utc)
    db.flush()
    return raw


def enforce_password_reset_cooldown(user: User) -> None:
    if user.password_reset_last_sent_at is None:
        return
    last = user.password_reset_last_sent_at
    if last.tzinfo is None:
        last = last.replace(tzinfo=timezone.utc)
    delta = datetime.now(timezone.utc) - last
    if delta.total_seconds() < _RESEND_COOLDOWN_SEC:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Please wait before requesting another code",
        )


def issue_password_reset_code(user: User, db: Session) -> str:
    raw = f"{secrets.randbelow(900000) + 100000:06d}"
    user.password_reset_code_hash = hash_email_verification_code(raw)
    user.password_reset_expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=_PASSWORD_RESET_TTL_MIN
    )
    user.password_reset_last_sent_at = datetime.now(timezone.utc)
    db.flush()
    return raw
