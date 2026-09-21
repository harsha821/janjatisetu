from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from fpdf import FPDF
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..models import Application, Deficiency, Document, Notification, Scheme, StudentProfile, User
from ..schemas import ApplicationCreateIn, ApplicationUpdateIn, ResolveDeficiencyIn
from ..services.cases import audit
from ..services.doc_requirements import required_steps
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
        if dup.status == "DRAFT":
            filled = autofill(profile, scheme_code)
            current = dict(dup.form_data or {})
            changed = False
            for k, v in filled.items():
                if v is not None and (current.get(k) is None or current.get(k) == ""):
                    current[k] = v
                    changed = True
            if changed:
                current["_autofilled"] = sorted(list(set(current.get("_autofilled", []) + filled.get("_autofilled", []))))
                dup.form_data = current
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
    if app.status == "DRAFT":
        p = get_profile(db, user)
        filled = autofill(p, app.scheme_code)
        current = dict(app.form_data or {})
        changed = False
        for k, v in filled.items():
            if v is not None and (current.get(k) is None or current.get(k) == ""):
                current[k] = v
                changed = True
        if changed:
            current["_autofilled"] = sorted(list(set(current.get("_autofilled", []) + filled.get("_autofilled", []))))
            app.form_data = current
            db.commit()
    return application_out(app, db.get(Scheme, app.scheme_code), detail=True)


@router.post("/applications/{app_id}/autofill")
def autofill_application(app_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    if app.status not in EDITABLE:
        raise HTTPException(409, "This application can no longer be edited")
    p = get_profile(db, user)
    filled = autofill(p, app.scheme_code)
    current = dict(app.form_data or {})
    for k, v in filled.items():
        if v is not None or k not in current:
            current[k] = v
    current["_autofilled"] = sorted(list(set(current.get("_autofilled", []) + filled.get("_autofilled", []))))
    app.form_data = current
    app.version += 1
    db.commit()
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


@router.get("/applications/{app_id}/receipt.pdf")
def download_receipt(app_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    app = _own(db, user, app_id)
    scheme = db.get(Scheme, app.scheme_code)
    
    pdf = FPDF()
    pdf.add_page()
    
    # Title Block
    pdf.set_fill_color(0, 41, 112)  # Dark Blue
    pdf.set_text_color(255, 255, 255) # White
    pdf.set_font("helvetica", "B", 18)
    pdf.cell(0, 15, "JanjatiSetu - Application Receipt", ln=True, align="C", fill=True)
    pdf.ln(10)
    
    # Basic Info
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("helvetica", "", 12)
    pdf.cell(0, 8, f"Application ID: JS-APP-{app.id}", ln=True)
    pdf.cell(0, 8, f"Scheme: {scheme.name if scheme else app.scheme_code}", ln=True)
    pdf.set_text_color(0, 128, 0) if app.status in ("SUBMITTED", "VERIFIED") else pdf.set_text_color(230, 81, 0)
    pdf.cell(0, 8, f"Status: {app.status}", ln=True)
    pdf.set_text_color(0, 0, 0)
    pdf.cell(0, 8, f"Submitted On: {app.submitted_at.strftime('%Y-%m-%d %H:%M') if app.submitted_at else 'N/A'}", ln=True)
    pdf.ln(10)
    
    # Applicant Details Header
    pdf.set_fill_color(226, 238, 248) # Light Blue
    pdf.set_text_color(0, 41, 112) # Dark Blue
    pdf.set_font("helvetica", "B", 14)
    pdf.cell(0, 10, "  Applicant Details", ln=True, fill=True)
    
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("helvetica", "", 12)
    pdf.cell(0, 8, f"  Name: {user.full_name}", ln=True)
    
    if app.form_data:
        pdf.ln(10)
        pdf.set_fill_color(226, 238, 248)
        pdf.set_text_color(0, 41, 112)
        pdf.set_font("helvetica", "B", 14)
        pdf.cell(0, 10, "  Application Data", ln=True, fill=True)
        pdf.set_text_color(50, 50, 50)
        pdf.set_font("helvetica", "", 10)
        for k, v in app.form_data.items():
            if not k.startswith("_"):
                label = k.replace('_', ' ').title()
                val = str(v).encode('latin-1', 'replace').decode('latin-1')
                pdf.cell(0, 6, f"  {label}: {val}", ln=True)
                
    pdf_bytes = pdf.output()
    return Response(
        content=bytes(pdf_bytes), 
        media_type="application/pdf", 
        headers={"Content-Disposition": f'attachment; filename="JS-APP-{app.id}.pdf"'}
    )


# ---------------------------------- verification checklist endpoints ---------


@router.get("/applications/{app_id}/verification-checklist")
def get_verification_checklist(
    app_id: int,
    user: User = Depends(student_only),
    db: Session = Depends(get_db),
):
    """Return the scheme-aware verification step list for a specific application.

    Each step is annotated with:
    - ``status``: VERIFIED | PENDING | NOT_APPLICABLE
    - ``document_id``: wallet document ID if one matches (nullable)
    - ``source_check``: entry from the application's verification_report (nullable)
    """
    app = _own(db, user, app_id)
    profile = db.scalar(select(StudentProfile).where(StudentProfile.user_id == user.id))

    scheme_code: str = app.scheme_code
    course_level: str = (profile.course_level or "") if profile else ""
    semester: Optional[int] = profile.semester if profile else None
    category: str = (profile.category or "ST") if profile else "ST"

    steps = required_steps(scheme_code, course_level, semester, category)

    # Build a lookup: doc_type -> list of wallet documents owned by the user
    wallet_docs = list(
        db.scalars(select(Document).where(Document.user_id == user.id))
    )
    doc_by_type: dict[str, list[Document]] = {}
    for d in wallet_docs:
        doc_by_type.setdefault(d.doc_type, []).append(d)

    # Build a lookup: source -> check result from the verification report
    report = app.verification_report or {}
    checks_by_source: dict[str, dict] = {
        c["source"]: c for c in (report.get("checks") or [])
    }

    enriched = []
    for step in steps:
        if not step["applicable"]:
            enriched.append({**step, "status": "NOT_APPLICABLE", "document_id": None, "source_check": None})
            continue

        matched_docs = doc_by_type.get(step["doc_type"], [])
        # Prefer a DigiLocker-verified document if available
        verified_doc = next((d for d in matched_docs if d.verified), None)
        any_doc = verified_doc or (matched_docs[0] if matched_docs else None)

        status = "VERIFIED" if (verified_doc is not None) else "PENDING"
        source_check = checks_by_source.get(step["source"])

        enriched.append({
            **step,
            "status": status,
            "document_id": any_doc.id if any_doc else None,
            "source_check": source_check,
        })

    verified_count = sum(1 for s in enriched if s["status"] == "VERIFIED")
    applicable_count = sum(1 for s in enriched if s["status"] != "NOT_APPLICABLE")

    return {
        "app_id": app_id,
        "scheme_code": scheme_code,
        "course_level": course_level,
        "semester": semester,
        "total": applicable_count,
        "verified": verified_count,
        "steps": enriched,
    }


@router.get("/verification-requirements")
def get_verification_requirements(
    scheme_code: str = Query(..., description="Scheme code, e.g. PRE_MATRIC or POST_MATRIC"),
    course_level: str = Query(..., description="Student course level, e.g. CLASS_10, UG"),
    semester: Optional[int] = Query(None, description="Current semester (1-based). Only affects UNIVERSITY_MARKSHEET applicability."),
    category: str = Query("ST", description="Reservation category. Default: ST"),
):
    """Standalone endpoint — no auth required.

    Returns the raw verification step list for a (scheme, course_level, semester)
    combination. Useful before an application has been created (e.g. on the
    scheme discovery / eligibility screen).
    """
    steps = required_steps(scheme_code, course_level, semester, category)
    applicable = [s for s in steps if s["applicable"]]
    return {
        "scheme_code": scheme_code,
        "course_level": course_level,
        "semester": semester,
        "total": len(applicable),
        "steps": steps,
    }
