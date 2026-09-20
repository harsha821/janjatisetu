"""Security primitives.

Passwords    bcrypt via passlib.
Aadhaar / bank account numbers   never stored in the clear.
  - hash_identifier: keyed HMAC-SHA256, used for lookups (UIDAI restriction:
    only a keyed hash or the last 4 digits may be stored, never the number).
  - encrypt_field / decrypt_field: Fernet, used when the plaintext must be
    recoverable (bank account number, for DBT payment processing).
JWT          HS256 access tokens carrying the user id and role.
"""
import base64
import hashlib
import hmac
from datetime import datetime, timedelta, timezone
from typing import Any

import jwt
from cryptography.fernet import Fernet
import bcrypt

from .config import settings

def hash_password(password: str) -> str:
    pw_bytes = password.encode("utf-8")[:72]
    return bcrypt.hashpw(pw_bytes, bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        pw_bytes = password.encode("utf-8")[:72]
        return bcrypt.checkpw(pw_bytes, password_hash.encode("utf-8"))
    except Exception:
        return False


def hash_identifier(value: str) -> str:
    """Keyed HMAC-SHA256 hex digest, used so Aadhaar/account numbers are never stored raw."""
    key = settings.secret_key.encode("utf-8")
    return hmac.new(key, value.encode("utf-8"), hashlib.sha256).hexdigest()


def _fernet() -> Fernet:
    raw = settings.field_encryption_key
    if raw:
        key = raw.encode("utf-8")
    else:  # dev-only fallback so the app runs without extra setup; set FIELD_ENCRYPTION_KEY in production
        key = base64.urlsafe_b64encode(hashlib.sha256(settings.secret_key.encode("utf-8")).digest())
    return Fernet(key)


def encrypt_field(value: str) -> str:
    return _fernet().encrypt(value.encode("utf-8")).decode("utf-8")


def decrypt_field(token: str) -> str:
    return _fernet().decrypt(token.encode("utf-8")).decode("utf-8")


# --------------------------------------------------------------------- JWT
def create_access_token(subject: int, role: str, expires_minutes: int | None = None) -> str:
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(subject),
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=expires_minutes or settings.access_token_expire_minutes),
    }
    return jwt.encode(payload, settings.secret_key, algorithm=settings.algorithm)


def decode_access_token(token: str) -> dict:
    return jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
