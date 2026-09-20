from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import admin_only, staff_only
from ..integrations.gateway import Gateway
from ..models import (Application, AuditLog, CoverageGap, Document, ExceptionCase, Outreach, ScholarshipRecord,
                      Scheme, SourceStudentRecord, StudentProfile, User)
from ..schemas import AdminActionIn, ExceptionResolveIn, GapResolveIn, OutreachIn
from ..services import coverage_gap as gaps
from ..services.cases import audit, resolve_case
from ..services.student import application_out, doc_out, profile_out
from ..services.submission import push_to_portal
from ..services.workflow import WorkflowError, raise_deficiency, transition

router = APIRouter(prefix="/admin", tags=["admin"])


# ------------------------------------------------------------------ overview
@router.get("/overview")
def overview(user: User = Depends(staff_only), db: Session = Depends(get_db)):
    by_status = dict(db.execute(select(Application.status, func.count()).group_by(Application.status)).all())
    by_scheme = dict(db.execute(select(Application.scheme_code, func.count()).group_by(Application.scheme_code)).all())
    cases = dict(db.execute(select(ExceptionCase.status, func.count()).group_by(ExceptionCase.status)).all())
    open_by_kind = dict(db.execute(select(ExceptionCase.kind, func.count()).where(ExceptionCase.status == "OPEN")
                                   .group_by(ExceptionCase.kind)).all())
    return {
        "applications": {"total": sum(by_status.values()), "by_status": by_status, "by_scheme": by_scheme},
        "exceptions": {"open": cases.get("OPEN", 0), "by_kind": open_by_kind},
        "money": {"sanctioned": db.scalar(select(func.coalesce(func.sum(Application.sanctioned_amount), 0))),
                  "paid": db.scalar(select(func.coalesce(func.sum(Application.paid_amount), 0)))},
        "students": db.scalar(select(func.count()).select_from(User).where(User.role == "STUDENT")),
        "coverage": gaps.funnel(db) if user.role == "ADMIN" else None,
    }


# -------------------------------------------------------------- applications
@router.get("/applications")
def list_applications(status: str | None = None, scheme: str | None = None, district: str | None = None,
                      q: str | None = Query(default=None, max_length=60), limit: int = Query(50, le=200), offset: int = 0,
                      user: User = Depends(staff_only), db: Session = Depends(get_db)):
    conds = [Application.status != "DRAFT"]
    if status:
        conds.append(Application.status == status)
    if scheme:
        conds.append(Application.scheme_code == scheme)
    if district:
        conds.append(StudentProfile.district == district)
    if q:
        like = f"%{q}%"
        conds.append(or_(User.full_name.ilike(like), Application.external_ref.ilike(like)))
    joins = ((User, User.id == Application.user_id), (StudentProfile, StudentProfile.user_id == User.id))
    count_stmt = select(func.count(Application.id)).select_from(Application)
    stmt = select(Application, User.full_name, StudentProfile.district, StudentProfile.state).select_from(Application)
    for target, on in joins:
        count_stmt, stmt = count_stmt.join(target, on), stmt.join(target, on)
    total = db.scalar(count_stmt.where(*conds))
    rows = db.execute(stmt.where(*conds).order_by(Application.updated_at.desc()).limit(limit).offset(offset)).all()
    open_cases = dict(db.execute(select(ExceptionCase.application_id, func.count()).where(
        ExceptionCase.status == "OPEN", ExceptionCase.application_id.is_not(None)).group_by(ExceptionCase.application_id)).all())
    return {"total": total, "items": [
        {"id": a.id, "student": name, "district": dist, "state": state, "scheme_code": a.scheme_code, "status": a.status,
         "external_ref": a.external_ref, "portal_sync": a.portal_sync, "open_cases": open_cases.get(a.id, 0),
         "submitted_at": a.submitted_at.isoformat() if a.submitted_at else None, "updated_at": a.updated_at.isoformat()}
        for a, name, dist, state in rows]}


@router.get("/applications/{app_id}")
def application_detail(app_id: int, user: User = Depends(staff_only), db: Session = Depends(get_db)):
    app = db.get(Application, app_id)
    if not app:
        raise HTTPException(404, "Application not found")
    student = db.get(User, app.user_id)
    profile = db.scalar(select(StudentProfile).where(StudentProfile.user_id == app.user_id))
    cases = db.scalars(select(ExceptionCase).where(ExceptionCase.application_id == app.id).order_by(ExceptionCase.id.desc()))
    docs = db.scalars(select(Document).where(Document.id.in_(app.document_ids or [])))
    audit(db, user, "VIEW_STUDENT_DATA", "application", app.id, student_id=student.id)
    db.commit()
    prof = profile_out(profile)
    prof.pop("phone", None)  # reviewers see masked identifiers only
    return {"application": application_out(app, db.get(Scheme, app.scheme_code), detail=True), "student": prof,
            "documents": [doc_out(d) for d in docs], "cases": [_case(c) for c in cases]}


@router.post("/applications/{app_id}/action")
def application_action(app_id: int, body: AdminActionIn, user: User = Depends(staff_only), db: Session = Depends(get_db)):
    app = db.get(Application, app_id)
    if not app:
        raise HTTPException(404, "Application not found")
    scheme = db.get(Scheme, app.scheme_code)
    name, act = scheme.short_name, body.action
    try:
        if act == "START_REVIEW":
            transition(db, app, "UNDER_VERIFICATION", actor_role=user.role, note=body.note, scheme_name=name)
        elif act == "RAISE_DEFICIENCY":
            if not (body.note or "").strip():
                raise HTTPException(422, "Say what the student needs to fix")
            raise_deficiency(db, app, body.note, doc_type=body.doc_type, raised_by=user.id, scheme_name=name)
        elif act == "VERIFY":
            open_n = db.scalar(select(func.count()).select_from(ExceptionCase).where(
                ExceptionCase.application_id == app.id, ExceptionCase.status.in_(("OPEN", "ESCALATED"))))
            if open_n:
                raise HTTPException(409, f"Resolve or dismiss the {open_n} open review case(s) before verifying")
            transition(db, app, "VERIFIED", actor_role=user.role, note=body.note, scheme_name=name)
        elif act == "SANCTION":
            if not body.amount:
                raise HTTPException(422, "Enter the sanctioned amount")
            transition(db, app, "SANCTIONED", actor_role=user.role, amount=body.amount, note=body.note, scheme_name=name)
        elif act == "PAY":
            if not body.amount or not body.utr:
                raise HTTPException(422, "Enter the amount and the payment reference (UTR)")
            transition(db, app, "DBT_PAID", actor_role=user.role, amount=body.amount, reference=body.utr, scheme_name=name)
        elif act == "REJECT":
            transition(db, app, "REJECTED", actor_role=user.role, note=body.note, scheme_name=name)
        elif act == "RETRY_PUSH":
            profile = db.scalar(select(StudentProfile).where(StudentProfile.user_id == app.user_id))
            if app.portal_sync != "PENDING_PUSH":
                raise HTTPException(409, "Nothing to retry")
            if not push_to_portal(db, app, scheme, profile, Gateway(db)):
                db.commit()
                raise HTTPException(503, "The portal is still unavailable")
    except WorkflowError as exc:
        raise HTTPException(409, str(exc))
    if app.external_ref:  # keep the (mock) portal record in step
        rec = db.scalar(select(ScholarshipRecord).where(ScholarshipRecord.external_ref == app.external_ref))
        if rec:
            rec.status = app.status
    audit(db, user, f"APP_{act}", "application", app.id, note=body.note)
    db.commit()
    return application_out(app, scheme, detail=True)


# --------------------------------------------------------------- exceptions
def _case(c: ExceptionCase) -> dict:
    return {"id": c.id, "kind": c.kind, "severity": c.severity, "title": c.title, "status": c.status,
            "user_id": c.user_id, "application_id": c.application_id, "details": c.details,
            "resolution_note": c.resolution_note, "created_at": c.created_at.isoformat()}


@router.get("/exceptions")
def list_exceptions(status: str = "OPEN", kind: str | None = None, limit: int = Query(100, le=300),
                    user: User = Depends(staff_only), db: Session = Depends(get_db)):
    stmt = select(ExceptionCase).where(ExceptionCase.status == status)
    if kind:
        stmt = stmt.where(ExceptionCase.kind == kind)
    order = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
    rows = sorted(db.scalars(stmt.order_by(ExceptionCase.id.desc()).limit(limit)), key=lambda c: order.get(c.severity, 3))
    return [_case(c) for c in rows]


@router.post("/exceptions/{case_id}/resolve")
def resolve_exception(case_id: int, body: ExceptionResolveIn, user: User = Depends(staff_only), db: Session = Depends(get_db)):
    case = db.get(ExceptionCase, case_id)
    if not case:
        raise HTTPException(404, "Case not found")
    if case.status in ("RESOLVED", "DISMISSED"):
        raise HTTPException(409, "This case is already closed")
    resolve_case(db, case, body.resolution, body.note, user.id)
    audit(db, user, "RESOLVE_CASE", "exception", case.id, resolution=body.resolution)
    db.commit()
    return _case(case)


# ------------------------------------------------------------ coverage gap
@router.post("/coverage-gap/run")
def run_gap_detection(user: User = Depends(admin_only), db: Session = Depends(get_db)):
    result = gaps.run_detection(db)
    audit(db, user, "RUN_COVERAGE_GAP", "coverage", None, **{k: v for k, v in result.items() if k != "note"})
    db.commit()
    return result


@router.get("/coverage-gap/summary")
def gap_summary(user: User = Depends(admin_only), db: Session = Depends(get_db)):
    return {"funnel": gaps.funnel(db), "districts": gaps.by_district(db)}


@router.get("/coverage-gap")
def list_gaps(state: str | None = None, district: str | None = None, limit: int = Query(100, le=500), offset: int = 0,
              user: User = Depends(admin_only), db: Session = Depends(get_db)):
    conds = []
    if state:
        conds.append(CoverageGap.state == state)
    if district:
        conds.append(SourceStudentRecord.district == district)
    on = SourceStudentRecord.id == CoverageGap.source_record_id
    total = db.scalar(select(func.count(CoverageGap.id)).select_from(CoverageGap).join(SourceStudentRecord, on).where(*conds))
    rows = db.execute(select(CoverageGap, SourceStudentRecord).select_from(CoverageGap).join(SourceStudentRecord, on)
                      .where(*conds).order_by(CoverageGap.id).limit(limit).offset(offset)).all()
    last_outreach = {}
    if rows:
        for o in db.scalars(select(Outreach).where(Outreach.gap_id.in_([g.id for g, _ in rows])).order_by(Outreach.id)):
            last_outreach[o.gap_id] = o  # later rows overwrite earlier ones
    items = [_gap_item(g, src, last_outreach.get(g.id)) for g, src in rows]
    audit(db, user, "VIEW_COVERAGE_GAPS", "coverage", None, count=len(rows))
    db.commit()
    return {"total": total, "note": gaps.DISCLAIMER, "items": items}


def _gap_item(g: CoverageGap, s: SourceStudentRecord, last: Outreach | None = None) -> dict:
    return {"id": g.id, "state": g.state, "reason": g.reason, "possible_schemes": g.possible_schemes,
            "name": s.name, "state_name": s.state, "district": s.district, "class_level": s.class_level,
            "institution_name": s.institution_name, "source": s.source,
            "outreach_channel": last.channel if last else None, "outreach_status": last.status if last else None}


@router.post("/coverage-gap/{gap_id}/resolve")
def resolve_gap(gap_id: int, body: GapResolveIn, user: User = Depends(admin_only), db: Session = Depends(get_db)):
    """Reviewer closes a gap by hand (DISMISS needs a reason, MARK_APPLIED) or REOPENs it for re-validation."""
    gap = db.get(CoverageGap, gap_id)
    if not gap:
        raise HTTPException(404, "Coverage gap not found")
    if body.action == "DISMISS" and not (body.note or "").strip():
        raise HTTPException(400, "A written reason is required to dismiss a gap")
    before = gap.state
    try:
        gaps.resolve_gap(db, gap, body.action, body.note)
    except gaps.GapError as e:
        raise HTTPException(409, str(e))
    audit(db, user, "RESOLVE_COVERAGE_GAP", "coverage_gap", gap.id, resolution=body.action, from_state=before,
          to_state=gap.state, note=(body.note or "").strip() or None)
    item = _gap_item(gap, gap.source_record)
    db.commit()
    return item


@router.post("/coverage-gap/outreach")
def outreach(body: OutreachIn, user: User = Depends(admin_only), db: Session = Depends(get_db)):
    result = gaps.send_outreach(db, body.gap_ids, body.channel, body.message, user.id)
    audit(db, user, "SEND_OUTREACH", "coverage", None, channel=body.channel, **result)
    db.commit()
    return result


# -------------------------------------------------------------------- audit
@router.get("/audit")
def audit_log(limit: int = Query(100, le=500), user: User = Depends(admin_only), db: Session = Depends(get_db)):
    rows = db.scalars(select(AuditLog).order_by(AuditLog.id.desc()).limit(limit))
    return [{"id": r.id, "at": r.created_at.isoformat(), "actor_id": r.actor_id, "role": r.actor_role, "action": r.action,
             "entity": r.entity, "entity_id": r.entity_id, "meta": r.meta} for r in rows]
