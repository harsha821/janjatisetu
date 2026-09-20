"""Application lifecycle operations against the database (rules live in lifecycle.py)."""
# pyrefly: ignore [missing-import]
from sqlalchemy.orm import Session

from ..models import Application, ApplicationEvent, Deficiency, utcnow
from .lifecycle import STAGE_OF, build_timeline, can_transition
from .notify import notify

_MESSAGES = {
    "SUBMITTED": ("Application submitted", "Your {scheme} application was sent. We are checking your details."),
    "UNDER_VERIFICATION": ("Under verification", "Your {scheme} application is being verified."),
    "DEFICIENCY": ("Action needed", "Your {scheme} application needs a correction. Open it to see what to fix."),
    "VERIFIED": ("Verified", "Your {scheme} application has been verified."),
    "SANCTIONED": ("Scholarship sanctioned", "Your {scheme} scholarship was sanctioned."),
    "DBT_PAID": ("Payment sent to your bank", "Your {scheme} payment has been credited to your bank account."),
    "REJECTED": ("Application not approved", "Your {scheme} application was not approved. Open it to read the reason."),
}
_KIND = {"DEFICIENCY": "DEFICIENCY", "SANCTIONED": "PAYMENT", "DBT_PAID": "PAYMENT"}


class WorkflowError(ValueError):
    pass


def timeline_for(app: Application) -> list[dict]:
    events = [{"stage": e.stage, "created_at": e.created_at} for e in app.events]
    ever = any(True for _ in app.deficiencies)
    open_def = any(not d.resolved for d in app.deficiencies)
    return build_timeline(app.status, events, ever, open_def)


def record_event(db: Session, app: Application, stage: str, status: str, *, note: str | None = None,
                 actor_role: str = "SYSTEM", amount: float | None = None, reference: str | None = None) -> ApplicationEvent:
    ev = ApplicationEvent(application=app, stage=stage, status=status, note=note, actor_role=actor_role,
                          amount=amount, reference=reference)
    db.add(ev)
    return ev


def transition(db: Session, app: Application, new_status: str, *, actor_role: str = "SYSTEM", note: str | None = None,
               amount: float | None = None, reference: str | None = None, scheme_name: str = "scholarship") -> None:
    if not can_transition(app.status, new_status):
        raise WorkflowError(f"Cannot move an application from {app.status} to {new_status}")
    if new_status == "REJECTED" and not (note or "").strip():
        raise WorkflowError("A reason is required to reject an application")
    app.status = new_status
    app.version += 1
    app.updated_at = utcnow()
    if new_status == "SUBMITTED":
        app.submitted_at = utcnow()
    if new_status == "SANCTIONED":
        app.sanctioned_amount = amount
    if new_status == "DBT_PAID":
        app.paid_amount, app.utr = amount, reference
    record_event(db, app, STAGE_OF[new_status], new_status, note=note, actor_role=actor_role, amount=amount, reference=reference)
    if new_status in _MESSAGES:
        title, body = _MESSAGES[new_status]
        text = body.format(scheme=scheme_name)
        if new_status == "REJECTED" and note:
            text += f" Reason: {note}"
        notify(db, app.user_id, title, text, kind=_KIND.get(new_status, "STATUS"), data={"application_id": app.id})


def raise_deficiency(db: Session, app: Application, message: str, *, doc_type: str | None, raised_by: int | None,
                     scheme_name: str) -> Deficiency:
    d = Deficiency(application=app, message=message, doc_type=doc_type, raised_by=raised_by)
    db.add(d)
    transition(db, app, "DEFICIENCY", actor_role="VERIFIER", note=message, scheme_name=scheme_name)
    return d


def resolve_deficiency(db: Session, app: Application, deficiency: Deficiency, note: str, scheme_name: str) -> None:
    if deficiency.resolved:
        raise WorkflowError("This correction was already submitted")
    deficiency.resolved, deficiency.resolution_note, deficiency.resolved_at = True, note, utcnow()
    if all(d.resolved for d in app.deficiencies):
        transition(db, app, "UNDER_VERIFICATION", actor_role="STUDENT", note="Correction submitted", scheme_name=scheme_name)
