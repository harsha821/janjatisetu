from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..models import Notification, User

router = APIRouter(prefix="/notifications", tags=["notifications"])


def _out(n: Notification) -> dict:
    return {"id": n.id, "title": n.title, "body": n.body, "kind": n.kind, "data": n.data,
            "is_read": n.is_read, "created_at": n.created_at.isoformat() if n.created_at else None}


@router.get("")
def list_notifications(unread_only: bool = False, limit: int = Query(50, le=200),
                       user: User = Depends(student_only), db: Session = Depends(get_db)):
    stmt = select(Notification).where(Notification.user_id == user.id)
    if unread_only:
        stmt = stmt.where(Notification.is_read.is_(False))
    rows = db.scalars(stmt.order_by(Notification.id.desc()).limit(limit))
    return [_out(n) for n in rows]


@router.get("/unread-count")
def unread_count(user: User = Depends(student_only), db: Session = Depends(get_db)):
    n = db.scalar(select(func.count()).select_from(Notification).where(
        Notification.user_id == user.id, Notification.is_read.is_(False))) or 0
    return {"unread": n}


@router.post("/{notification_id}/read")
def mark_read(notification_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    n = db.get(Notification, notification_id)
    if not n or n.user_id != user.id:
        raise HTTPException(404, "Notification not found")
    n.is_read = True
    db.commit()
    return _out(n)


@router.post("/read-all")
def mark_all_read(user: User = Depends(student_only), db: Session = Depends(get_db)):
    rows = db.scalars(select(Notification).where(Notification.user_id == user.id, Notification.is_read.is_(False)))
    count = 0
    for n in rows:
        n.is_read = True
        count += 1
    db.commit()
    return {"marked_read": count}
