"""DigiLocker sandbox OAuth 2.0 integration service.

Flow:
  1. GET /wallet/digilocker/connect  → returns authorization_url
  2. User grants consent on DigiLocker sandbox portal
  3. DigiLocker redirects to DIGILOCKER_REDIRECT_URI with ?code=&state=
  4. GET /wallet/digilocker/callback  → exchanges code for access_token, stores encrypted
  5. Subsequent GET /wallet/digilocker calls use the stored token

Sandbox base URL : https://sandbox.digilocker.gov.in
Production URL   : https://api.digilocker.gov.in

Reference: https://api.digilocker.gov.in/docs
"""
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import httpx

from ..config import settings

# DigiLocker sandbox OAuth2 endpoints (path only — base URL from settings)
_AUTH_PATH = "/public/oauth2/1/authorize"
_TOKEN_PATH = "/public/oauth2/1/token"
_ISSUED_PATH = "/public/oauth2/3/xml/eaadhaar"   # generic issued-docs list
_ISSUED_DOCS_PATH = "/public/oauth2/1/files/issued"
_PULL_PATH = "/public/oauth2/3/xml/{uri}"


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def _base() -> str:
    return settings.digilocker_base_url.rstrip("/")


def _sandbox_configured() -> bool:
    """True when the operator has filled in DigiLocker credentials in .env."""
    return bool(settings.digilocker_client_id and settings.digilocker_client_secret)


# ---------------------------------------------------------------------------
# public API
# ---------------------------------------------------------------------------

def generate_state() -> str:
    """Cryptographically random CSRF state token."""
    return secrets.token_urlsafe(32)


def authorization_url(state: str) -> str:
    """Build the DigiLocker consent URL the student should visit."""
    params = {
        "response_type": "code",
        "client_id": settings.digilocker_client_id,
        "redirect_uri": settings.digilocker_redirect_uri,
        "state": state,
        "scope": "openid",
    }
    query = "&".join(f"{k}={v}" for k, v in params.items())
    return f"{_base()}{_AUTH_PATH}?{query}"


def exchange_code(code: str) -> dict:
    """Exchange an authorization code for an access token.

    Returns dict with keys: access_token, token_type, expires_in, refresh_token (optional).
    Raises httpx.HTTPError on failure.
    """
    r = httpx.post(
        f"{_base()}{_TOKEN_PATH}",
        data={
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": settings.digilocker_redirect_uri,
            "client_id": settings.digilocker_client_id,
            "client_secret": settings.digilocker_client_secret,
        },
        timeout=10,
    )
    r.raise_for_status()
    return r.json()


def token_expiry(expires_in: int) -> datetime:
    """Compute UTC expiry datetime from expires_in seconds."""
    return datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(seconds=expires_in - 30)


def list_issued_documents(access_token: str) -> list[dict]:
    """Return issued documents from DigiLocker sandbox.

    Response shape (sandbox):
      { "items": [{ "name": "...", "type": "...", "date": "...", "uri": "...", "issuer": "...", "doctype": "..." }] }

    We normalise each item to the same shape the mock gateway returns so the
    rest of the wallet code is unchanged.
    """
    r = httpx.get(
        f"{_base()}{_ISSUED_DOCS_PATH}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    r.raise_for_status()
    raw = r.json()

    items = raw.get("items", raw.get("documents", []))
    docs = []
    for item in items:
        docs.append({
            "uri": item.get("uri", ""),
            "doc_type": _map_doc_type(item.get("doctype") or item.get("type", "")),
            "issuer": item.get("issuer", "DigiLocker"),
            "doc_number": item.get("docnumber") or item.get("doc_number"),
            "issued_on": item.get("date") or item.get("issued_on"),
            "name": item.get("name", ""),
        })
    return docs


def fetch_document(access_token: str, uri: str) -> dict:
    """Fetch a single document's metadata from DigiLocker sandbox.

    Returns normalised dict matching the mock gateway's fetch response shape.
    """
    r = httpx.get(
        f"{_base()}/public/oauth2/1/file/{uri}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=10,
    )
    if r.status_code == 404:
        return {"found": False}
    r.raise_for_status()
    raw = r.json()
    return {
        "found": True,
        "uri": uri,
        "doc_type": _map_doc_type(raw.get("doctype") or raw.get("type", "")),
        "issuer": raw.get("issuer", "DigiLocker"),
        "doc_number": raw.get("docnumber") or raw.get("doc_number"),
        "issued_on": raw.get("date") or raw.get("issued_on"),
        "data": raw,
    }


# ---------------------------------------------------------------------------
# Token encryption/decryption (reuse Fernet key already in settings)
# ---------------------------------------------------------------------------

def _fernet():
    from cryptography.fernet import Fernet
    key = settings.field_encryption_key
    if not key:
        # Dev-only: generate a temporary key (not persisted, tokens lost on restart)
        key = Fernet.generate_key().decode()
    return Fernet(key.encode() if isinstance(key, str) else key)


def encrypt_token(token: str) -> str:
    return _fernet().encrypt(token.encode()).decode()


def decrypt_token(enc: str) -> Optional[str]:
    try:
        return _fernet().decrypt(enc.encode()).decode()
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Map DigiLocker document types → JanjatiSetu DOC_TYPES
_DL_TO_JANJATI: dict[str, str] = {
    "CASTECERT": "CASTE_CERT",
    "CASTECERTIFICATE": "CASTE_CERT",
    "INCOMECERT": "INCOME_CERT",
    "INCOMECERTIFICATE": "INCOME_CERT",
    "MARKSHEET": "MARKSHEET",
    "MARKSHEETCERTIFICATE": "MARKSHEET",
    "BANKPASSBOOK": "BANK_PASSBOOK",
    "ADMISSIONLETTER": "ADMISSION_LETTER",
    "NETJRF": "NET_JRF_CERT",
    "NETJRFCERT": "NET_JRF_CERT",
}

_VALID_DOC_TYPES = {"CASTE_CERT", "INCOME_CERT", "MARKSHEET", "BANK_PASSBOOK", "ADMISSION_LETTER", "NET_JRF_CERT"}


def _map_doc_type(raw: str) -> str:
    key = raw.upper().replace(" ", "").replace("_", "").replace("-", "")
    mapped = _DL_TO_JANJATI.get(key, raw.upper())
    # Return only valid types, else keep as-is (wallet will just show it)
    return mapped if mapped in _VALID_DOC_TYPES else raw.upper()


# ---------------------------------------------------------------------------
# High-level token lifecycle helpers (used by wallet router)
# ---------------------------------------------------------------------------

def store_token(user: object, token_data: dict) -> None:
    """Persist an encrypted DigiLocker access token on the User row.

    Caller is responsible for calling ``db.commit()`` after this function.
    """
    from datetime import datetime
    access_token = token_data.get("access_token", "")
    expires_in = int(token_data.get("expires_in", 3600))
    user.digilocker_token = encrypt_token(access_token)
    user.digilocker_token_expiry = token_expiry(expires_in)
    user.digilocker_state = None  # clear CSRF state


def get_valid_token(user: object) -> Optional[str]:
    """Return the decrypted access token if it exists and is not expired, else None."""
    from datetime import datetime
    if not user.digilocker_token or not user.digilocker_token_expiry:
        return None
    if user.digilocker_token_expiry < datetime.utcnow():
        return None
    return decrypt_token(user.digilocker_token)


def revoke_token(user: object) -> None:
    """Clear stored DigiLocker token fields (caller must commit)."""
    user.digilocker_token = None
    user.digilocker_token_expiry = None
    user.digilocker_state = None
