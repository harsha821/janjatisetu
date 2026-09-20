"""Exception-case management and audit logging.

An ExceptionCase is how a mismatch, an outage, an anomaly or an uncertain
match reaches a human reviewer. Nothing here ever rejects an application —
that only happens through the explicit REJECT admin action with a reason.
"""
from sqlalchemy.orm import Session

from ..models import AuditLog, ExceptionCase, User, utcnow


def open_case(db: Session, kind: str, title: str, *, user_id: int | None = None, application_id: int | None = None,
             severity: str = "MEDIUM", details: dict | None = None) -> ExceptionCase:
    case = ExceptionCase(kind=kind, severity=severity, user_id=user_id, application_id=application_id,
                        title=title, details=details or {})
    db.add(case)
    db.flush()
    return case


def resolve_case(db: Session, case: ExceptionCase, resolution: str, note: str | None, resolved_by: int) -> None:
    status = "DISMISSED" if resolution == "DISMISS" else "RESOLVED"
    case.status = status
    case.resolution_note = note
    case.resolved_by = resolved_by
    case.resolved_at = utcnow()


def audit(db: Session, actor: User, action: str, entity: str, entity_id: int | str | None = None, **meta) -> AuditLog:
    row = AuditLog(actor_id=actor.id, actor_role=actor.role, action=action, entity=entity,
                   entity_id=str(entity_id) if entity_id is not None else None, meta=meta)
    db.add(row)
    return row
