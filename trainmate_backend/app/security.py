import hashlib
import hmac
from datetime import datetime, timedelta, timezone

import bcrypt
from jose import JWTError, jwt

from app.config import settings


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))


def create_access_token(subject: str, user_id: int) -> str:
    expire = datetime.now(timezone.utc) + timedelta(minutes=settings.access_token_expire_minutes)
    to_encode = {"sub": subject, "uid": user_id, "exp": expire}
    return jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None


def hash_email_verification_code(raw_code: str) -> str:
    key = settings.jwt_secret_key.encode("utf-8")
    return hmac.new(key, raw_code.strip().encode("utf-8"), hashlib.sha256).hexdigest()


def verify_email_code(raw_code: str, stored_hash: str | None) -> bool:
    if not stored_hash or not raw_code:
        return False
    return hmac.compare_digest(hash_email_verification_code(raw_code), stored_hash)
