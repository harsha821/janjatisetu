"""Offline-first sync.

The app queues operations while offline and pushes them in order when
connectivity returns. Every operation has a client-generated op_id, and its
result is stored, so a retried batch never duplicates work.

Conflict policy: the server wins once a reviewer has touched an application.
Edits to anything past DRAFT / DEFICIENCY come back as CONFLICT with the
server copy, so the app can show what changed instead of overwriting it.
"""
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..models import Application, Document, Notification, Scheme, SyncReceipt, User
from ..schemas import ApplicationUpdateIn, ProfileIn, SyncOp, SyncPushIn
from ..services.cases import audit
from ..services.lifecycle import EDITABLE
from ..services.student import (application_out, doc_out, eligibility_for, get_profile, profile_out)
from ..services.submission import SubmissionError, submit_application
from .applications import create_draft, update_draft

router = APIRouter(prefix="/sync", tags=["sync"])


def _find(db: Session, user: User, op: SyncOp) -> Application | None:
    if op.application_id:
        app = db.get(Application, op.application_id)
    elif op.client_uuid:
        app = db.scalar(select(Application).where(Application.client_uuid == op.client_uuid))
    else:
        app = None
    return app if app and app.user_id == user.id else None


def _apply(db: Session, user: User, op: SyncOp) -> dict:
    profile = get_profile(db, user)
    if op.type == "CREATE_APPLICATION":
        app = create_draft(db, user, profile, op.payload["scheme_code"], op.payload.get("academic_year", "2026-27"), op.client_uuid)
        if op.payload.get("form_data") or op.payload.get("document_ids") is not None:
            update_draft(app, ApplicationUpdateIn(form_data=op.payload.get("form_data"),
                                                  document_ids=op.payload.get("document_ids")), db, user)
        return {"ok": True, "application": application_out(app, db.get(Scheme, app.scheme_code), detail=True)}

    if op.type in ("UPDATE_APPLICATION", "SUBMIT_APPLICATION"):
        app = _find(db, user, op)
        if not app:
            return {"ok": False, "error": "NOT_FOUND"}
        scheme = db.get(Scheme, app.scheme_code)
        if op.type == "UPDATE_APPLICATION":
            if app.status not in EDITABLE:
                return {"ok": False, "error": "CONFLICT", "application": application_out(app, scheme, detail=True)}
            update_draft(app, ApplicationUpdateIn(**op.payload), db, user)
            return {"ok": True, "application": application_out(app, scheme, detail=True)}
        if app.status != "DRAFT":
            return {"ok": True, "application": application_out(app, scheme, detail=True)}  # already submitted
        try:
            submit_application(db, app, user, profile)
        except SubmissionError as exc:
            return {"ok": False, "error": "REJECTED_BY_RULES", "detail": exc.detail,
                    "application": application_out(app, scheme, detail=True)}
        return {"ok": True, "application": application_out(app, scheme, detail=True)}

    if op.type == "UPDATE_PROFILE":
        data = ProfileIn(**op.payload).model_dump(exclude_unset=True, exclude={"aadhaar_number", "bank_account_number"})
        for k, v in data.items():
            setattr(profile, k, v)
        return {"ok": True, "profile": profile_out(profile)}
    return {"ok": False, "error": "UNKNOWN_OP"}


@router.post("/push")
def push(body: SyncPushIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    results = []
    for op in body.operations:
        receipt = db.get(SyncReceipt, op.op_id)
        if receipt:
            if receipt.user_id != user.id:
                raise HTTPException(409, "Duplicate operation id")
            results.append({"op_id": op.op_id, **receipt.result, "replayed": True})
            continue
        try:
            with db.begin_nested():  # one failed operation must not undo the others
                result = _apply(db, user, op)
        except HTTPException as exc:
            result = {"ok": False, "error": "HTTP_" + str(exc.status_code), "detail": exc.detail}
        except (KeyError, ValueError) as exc:
            result = {"ok": False, "error": "INVALID", "detail": str(exc)}
        db.add(SyncReceipt(op_id=op.op_id, user_id=user.id, result=result))
        results.append({"op_id": op.op_id, **result})
    audit(db, user, "SYNC_PUSH", "sync", user.id, operations=len(body.operations))
    db.commit()
    return {"results": results, "server_time": datetime.now(timezone.utc).isoformat()}


@router.get("/pull")
def pull(since: datetime | None = None, user: User = Depends(student_only), db: Session = Depends(get_db)):
    """Everything the app needs offline. Pass `since` for a delta of changed applications."""
    p = get_profile(db, user)
    schemes = {s.code: s for s in db.scalars(select(Scheme))}
    q = select(Application).where(Application.user_id == user.id)
    if since:
        q = q.where(Application.updated_at > since.replace(tzinfo=None))
    apps = [application_out(a, schemes.get(a.scheme_code), detail=True) for a in db.scalars(q)]
    notes = db.scalars(select(Notification).where(Notification.user_id == user.id).order_by(Notification.id.desc()).limit(50))
    db.commit()
    return {
        "server_time": datetime.now(timezone.utc).isoformat(),
        "profile": profile_out(p),
        "applications": apps,
        "documents": [doc_out(d) for d in db.scalars(select(Document).where(Document.user_id == user.id))],
        "eligibility": eligibility_for(db, p),
        "schemes": [{"code": s.code, "name": s.name, "short_name": s.short_name, "portal": s.portal,
                     "description": s.description, "documents": s.documents} for s in schemes.values()],
        "notifications": [{"id": n.id, "title": n.title, "body": n.body, "kind": n.kind, "is_read": n.is_read,
                           "created_at": n.created_at.isoformat() if n.created_at else None} for n in notes],
    }
