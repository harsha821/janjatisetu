from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..models import Application, Deficiency, Document, Notification, Scheme, StudentProfile, User
from ..schemas import ApplicationCreateIn, ApplicationUpdateIn, ResolveDeficiencyIn
from ..services.cases import audit
from ..services.lifecycle import EDITABLE
from ..services.student import (application_out, autofill, completeness, eligibility_for, get_profile)
from ..services.submission import SubmissionError, submit_application
from ..services.workflow import WorkflowError, resolve_deficiency

router = APIRouter(tags=["applications"])
_BLOCKED_FORM_KEYS = {"_autofilled"}  # written by the server only


def create_draft(db: Session, user: User, profile: StudentProfile, scheme_code: str, academic_year: str,
                 client_uuid: str | None) -> Application:
    """Idempotent: a repeated client_uuid (offline replay) returns the same draft."""
    if client_uuid:
        existing = db.scalar(select(Application).where(Application.client_uuid == client_uuid))
        if existing:
            if existing.user_id != user.id:
                raise HTTPException(409, "Duplicate client id")
            return existing
    scheme = db.get(Scheme, scheme_code)
    if not scheme or not scheme.active:
        raise HTTPException(404, "Scheme not found")
    dup = db.scalar(select(Application).where(Application.user_id == user.id, Application.scheme_code == scheme_code,
                                              Application.academic_year == academic_year))
    if dup:
        return dup  # one application per scheme per year: continue the existing one
    app = Application(user_id=user.id, scheme_code=scheme_code, academic_year=academic_year,
                      client_uuid=client_uuid, form_data=autofill(profile, scheme_code), document_ids=[])
    db.add(app)
    db.flush()
    from ..services.workflow import record_event

    record_event(db, app, "APPLICATION", "DRAFT", note="Draft created", actor_role="STUDENT")
    return app


def update_draft(app: Application, body: ApplicationUpdateIn, db: Session, user: User) -> None:
    if app.status not in EDITABLE:
        raise HTTPException(409, "This application can no longer be edited")
    if body.form_data is not None:
        merged = {**(app.form_data or {}), **{k: v for k, v in body.form_data.items() if k not in _BLOCKED_FORM_KEYS}}
        app.form_data = merged
    if body.document_ids is not None:
        owned = set(db.scalars(select(Document.id).where(Document.id.in_(body.document_ids), Document.user_id == user.id)))
        app.document_ids = sorted(owned)
    app.version += 1


def _own(db: Session, user: User, app_id: int) -> Application:
    app = db.get(Application, app_id)
    if not app or app.user_id != user.id:
        raise HTTPException(404, "Application not found")
    return app


@router.get("/eligibility")
def eligibility(user: User = Depends(student_only), db: Session = Depends(get_db)):
    p = get_profile(db, user)
    db.commit()
    return eligibility_for(db, p)


@router.get("/dashboard")
def dashboard(user: User = Depends(student_only), db: Session = Depends(get_db)):
    """One view over every scheme: status, verification, deficiencies, sanctions and DBT."""
    p = get_profile(db, user)
    schemes = {s.code: s for s in db.scalars(select(Scheme))}
    apps = list(db.scalars(select(Application).where(Application.user_id == user.id).order_by(Application.updated_at.desc())))
    items = [application_out(a, schemes.get(a.scheme_code)) for a in apps]

    next_step = None
    open_def = next((i for i in items if i["open_deficiencies"]), None)
    draft = next((i for i in items if i["status"] == "DRAFT"), None)
    if open_def:
        d = open_def["open_deficiencies"][0]
        next_step = {"kind": "DEFICIENCY", "application_id": open_def["id"], "title": f"Fix your {open_def['short_name']} application",
                     "body": d["message"]}
    elif draft:
        next_step = {"kind": "DRAFT", "application_id": draft["id"], "title": f"Finish your {draft['short_name']} application",
                     "body": "Your saved details are already filled in."}
    else:
        applied = {a.scheme_code for a in apps}
        elig = [e for e in eligibility_for(db, p) if e["status"] == "ELIGIBLE" and e["scheme_code"] not in applied]
        if elig:
            s = schemes[elig[0]["scheme_code"]]
            next_step = {"kind": "APPLY", "scheme_code": s.code, "title": f"You can apply for {s.short_name}", "body": s.description}
        elif completeness(p)["percent"] < 100:
            next_step = {"kind": "PROFILE", "title": "Complete your profile",
                         "body": "More details help us check which schemes you can apply for."}

    db.commit()
    return {
        "student": {"name": user.full_name, "verification": p.verification_status, "profile_percent": completeness(p)["percent"]},
        "applications": items,
        "next_step": next_step,
        "totals": {"sanctioned": sum(a.sanctioned_amount or 0 for a in apps), "paid": sum(a.paid_amount or 0 for a in apps)},
        "unread_notifications": db.scalar(select(func.count()).select_from(Notification).where(
            Notification.user_id == user.id, Notification.is_read.is_(False))) or 0,
    }


@router.post("/applications", status_code=201)
def create_application(body: ApplicationCreateIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    p = get_profile(db, user)
    app = create_draft(db, user, p, body.scheme_code, body.academic_year, body.client_uuid)
    audit(db, user, "CREATE_APPLICATION", "application", app.id, scheme=body.scheme_code)
    db.commit()
    return application_out(app, db.get(Scheme, app.scheme_code), detail=True)


@router.get("/applications/{app_id}")
def get_application(app_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    return application_out(app, db.get(Scheme, app.scheme_code), detail=True)


@router.put("/applications/{app_id}")
def edit_application(app_id: int, body: ApplicationUpdateIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    update_draft(app, body, db, user)
    db.commit()
    return application_out(app, db.get(Scheme, app.scheme_code), detail=True)


@router.post("/applications/{app_id}/submit")
def submit(app_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    if app.status != "DRAFT":
        raise HTTPException(409, "This application was already submitted")
    try:
        submit_application(db, app, user, get_profile(db, user))
    except SubmissionError as exc:
        db.rollback()
        raise HTTPException(exc.code, exc.detail)
    audit(db, user, "SUBMIT_APPLICATION", "application", app.id, scheme=app.scheme_code)
    db.commit()
    return application_out(app, db.get(Scheme, app.scheme_code), detail=True)


@router.get("/applications/{app_id}/timeline")
def timeline(app_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    a = application_out(_own(db, user, app_id), None, detail=True)
    return {"timeline": a["timeline"], "events": a["events"]}


@router.post("/applications/{app_id}/deficiencies/{def_id}/resolve")
def resolve(app_id: int, def_id: int, body: ResolveDeficiencyIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    d = db.get(Deficiency, def_id)
    if not d or d.application_id != app.id:
        raise HTTPException(404, "Correction not found")
    scheme = db.get(Scheme, app.scheme_code)
    if body.document_id:
        doc = db.get(Document, body.document_id)
        if not doc or doc.user_id != user.id:
            raise HTTPException(404, "Document not found")
        app.document_ids = sorted(set(app.document_ids or []) | {doc.id})
    try:
        resolve_deficiency(db, app, d, body.note, scheme.short_name)
    except WorkflowError as exc:
        raise HTTPException(409, str(exc))
    audit(db, user, "RESOLVE_DEFICIENCY", "application", app.id)
    db.commit()
    return application_out(app, scheme, detail=True)
