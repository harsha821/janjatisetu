"""Notification delivery: always an in-app row; FCM push and SMS are best-effort
and controlled by settings so the platform runs without either configured.
"""
import logging

from sqlalchemy.orm import Session

from ..config import settings
from ..models import Notification, User

log = logging.getLogger("janjatisetu.notify")


def notify(db: Session, user_id: int, title: str, body: str, *, kind: str = "INFO", data: dict | None = None) -> Notification:
    n = Notification(user_id=user_id, title=title, body=body, kind=kind, data=data or {})
    db.add(n)
    db.flush()
    if settings.fcm_enabled:
        _push_fcm(db, user_id, title, body, data or {})
    return n


def _push_fcm(db: Session, user_id: int, title: str, body: str, data: dict) -> None:
    user = db.get(User, user_id)
    if not user or not user.fcm_token:
        return
    try:
        import firebase_admin  # noqa: F401
        from firebase_admin import messaging

        messaging.send(messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in data.items()},
            token=user.fcm_token,
        ))
    except Exception:  # pragma: no cover - best-effort push, never blocks the request
        log.warning("FCM push failed for user %s", user_id, exc_info=True)


def send_sms(mobile: str, text: str) -> bool:
    if not settings.sms_enabled:
        log.info("SMS (disabled, not sent) to %s: %s", mobile, text)
        return False
    try:
        import httpx

        httpx.post("https://api.sms-provider.example/v1/send",
                   json={"to": mobile, "text": text, "sender_id": settings.sms_sender_id},
                   headers={"Authorization": f"Bearer {settings.sms_provider_api_key}"}, timeout=8)
        return True
    except Exception:  # pragma: no cover - best-effort, never blocks the caller
        log.warning("SMS send failed for %s", mobile, exc_info=True)
        return False
