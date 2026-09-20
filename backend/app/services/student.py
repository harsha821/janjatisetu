"""Shared helpers and serialisers used by the student-facing routers.

Keeps the DB <-> JSON boundary in one place so `applications.py`, `wallet.py`,
`sync.py` and `admin.py` stay thin and agree on the same shapes.
"""
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..models import Application, Consent, Document, Scheme, StudentProfile, User
from . import eligibility as E
from .lifecycle import ACTIVE_HOLDING
from .workflow import timeline_for

_PROFILE_COMPLETENESS_FIELDS = [
    "dob", "gender", "state", "district", "course_level", "institution_name",
    "annual_family_income", "apaar_id", "aadhaar_hash", "bank_account_hash",
]

_DOC_TO_PROFILE_FIELD = {
    "CASTE_CERT": ("category", lambda d: d.get("category")),
    "INCOME_CERT": ("annual_family_income", lambda d: d.get("amount")),
    "MARKSHEET": ("last_exam_percentage", lambda d: d.get("percentage")),
    "NET_JRF_CERT": ("ugc_nta_roll", lambda d: d.get("roll")),
}


def _iso(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    return v


# ------------------------------------------------------------------ profile
def get_profile(db: Session, user: User) -> StudentProfile:
    profile = db.scalar(select(StudentProfile).where(StudentProfile.user_id == user.id))
    if profile is None:
        profile = StudentProfile(user_id=user.id)
        db.add(profile)
        db.flush()
    return profile


def completeness(profile: StudentProfile) -> dict:
    filled = sum(1 for f in _PROFILE_COMPLETENESS_FIELDS if getattr(profile, f, None) not in (None, ""))
    total = len(_PROFILE_COMPLETENESS_FIELDS)
    missing = [f for f in _PROFILE_COMPLETENESS_FIELDS if getattr(profile, f, None) in (None, "")]
    return {"percent": round(100 * filled / total), "missing_fields": missing}


def consent_set(db: Session, user_id: int) -> set[str]:
    rows = db.scalars(select(Consent).where(Consent.user_id == user_id, Consent.granted.is_(True)))
    return {c.purpose for c in rows}


def profile_out(profile: StudentProfile) -> dict:
    user = profile.user
    return {
        "full_name": user.full_name if user else None,
        "phone": user.phone if user else None,
        "email": user.email if user else None,
        "language": user.language if user else "en",
        "dob": _iso(profile.dob), "gender": profile.gender, "category": profile.category,
        "tribe_name": profile.tribe_name, "is_pvtg": profile.is_pvtg,
        "state": profile.state, "district": profile.district, "lat": profile.lat, "lon": profile.lon,
        "course_level": profile.course_level, "course_name": profile.course_name,
        "institution_name": profile.institution_name, "institution_code": profile.institution_code,
        "institution_top_class_notified": profile.institution_top_class_notified,
        "last_exam_percentage": profile.last_exam_percentage, "apaar_id": profile.apaar_id,
        "aadhaar_last4": profile.aadhaar_last4, "bank_account_last4": profile.bank_account_last4,
        "ifsc": profile.ifsc, "annual_family_income": profile.annual_family_income,
        "ugc_nta_qualified": profile.ugc_nta_qualified, "ugc_nta_roll": profile.ugc_nta_roll,
        "foreign_admission": profile.foreign_admission, "active_scholarships": profile.active_scholarships or [],
        "verification_status": profile.verification_status, "verification_confidence": profile.verification_confidence,
        "completeness": completeness(profile)["percent"],
        "updated_at": _iso(profile.updated_at),
    }


def _profile_for_rules(profile: StudentProfile) -> dict:
    return {
        "category": profile.category, "course_level": profile.course_level, "dob": _iso(profile.dob),
        "annual_family_income": profile.annual_family_income, "is_pvtg": profile.is_pvtg,
        "foreign_admission": profile.foreign_admission, "last_exam_percentage": profile.last_exam_percentage,
        "ugc_nta_qualified": profile.ugc_nta_qualified,
    }


def eligibility_for(db: Session, profile: StudentProfile) -> list[dict]:
    schemes = list(db.scalars(select(Scheme).where(Scheme.active)))
    scheme_dicts = [{"code": s.code, "rules": s.rules, "conflicts_with": s.conflicts_with} for s in schemes]
    held = set(db.scalars(select(Application.scheme_code).where(
        Application.user_id == profile.user_id, Application.status.in_(ACTIVE_HOLDING))))
    active_codes = held | set(profile.active_scholarships or [])
    results = E.evaluate_all(_profile_for_rules(profile), scheme_dicts, active_codes)
    by_code = {s.code: s for s in schemes}
    return [{**r, "short_name": by_code[r["scheme_code"]].short_name} for r in results]


# ---------------------------------------------------------------- documents
def doc_out(doc: Document) -> dict:
    return {"id": doc.id, "doc_type": doc.doc_type, "source": doc.source, "uri": doc.uri,
            "file_name": doc.file_name, "issuer": doc.issuer, "doc_number": doc.doc_number,
            "issued_on": _iso(doc.issued_on), "verified": doc.verified, "created_at": _iso(doc.created_at)}


def apply_document_to_form(doc: Document, form: dict) -> dict:
    """Folds an attached document's extracted data into the application draft."""
    new_form = dict(form)
    mapping = _DOC_TO_PROFILE_FIELD.get(doc.doc_type)
    if mapping:
        field, extract = mapping
        value = extract(doc.extracted or {})
        if value is not None:
            new_form[field] = value
    docs_meta = dict(new_form.get("_documents_meta") or {})
    docs_meta[doc.doc_type] = {"document_id": doc.id, "verified": doc.verified}
    new_form["_documents_meta"] = docs_meta
    return new_form


# -------------------------------------------------------------- application
def autofill(profile: StudentProfile, scheme_code: str) -> dict:
    user = profile.user
    form = {
        "scheme_code": scheme_code,
        "applicant_name": user.full_name if user else None,
        "phone": user.phone if user else None,
        "dob": _iso(profile.dob), "gender": profile.gender, "category": profile.category,
        "tribe_name": profile.tribe_name, "is_pvtg": profile.is_pvtg,
        "state": profile.state, "district": profile.district,
        "course_level": profile.course_level, "course_name": profile.course_name,
        "institution_name": profile.institution_name, "institution_code": profile.institution_code,
        "apaar_id": profile.apaar_id, "annual_family_income": profile.annual_family_income,
        "bank_account_last4": profile.bank_account_last4, "ifsc": profile.ifsc,
        "last_exam_percentage": profile.last_exam_percentage,
    }
    form["_autofilled"] = sorted(k for k, v in form.items() if v not in (None, "") and k not in ("scheme_code",))
    return form


def application_out(app: Application, scheme: Scheme | None, detail: bool = False) -> dict:
    out = {
        "id": app.id, "scheme_code": app.scheme_code, "short_name": scheme.short_name if scheme else app.scheme_code,
        "academic_year": app.academic_year, "status": app.status, "external_ref": app.external_ref,
        "portal_sync": app.portal_sync, "sanctioned_amount": app.sanctioned_amount, "paid_amount": app.paid_amount,
        "utr": app.utr, "version": app.version, "submitted_at": _iso(app.submitted_at),
        "created_at": _iso(app.created_at), "updated_at": _iso(app.updated_at),
        "open_deficiencies": [{"id": d.id, "message": d.message, "doc_type": d.doc_type}
                              for d in app.deficiencies if not d.resolved],
        "timeline": timeline_for(app),
    }
    if detail:
        out["form_data"] = app.form_data
        out["document_ids"] = app.document_ids or []
        out["events"] = [{"stage": e.stage, "status": e.status, "note": e.note, "actor_role": e.actor_role,
                          "amount": e.amount, "reference": e.reference, "created_at": _iso(e.created_at)}
                         for e in app.events]
        out["deficiencies"] = [{"id": d.id, "message": d.message, "doc_type": d.doc_type, "resolved": d.resolved,
                                "resolution_note": d.resolution_note, "created_at": _iso(d.created_at),
                                "resolved_at": _iso(d.resolved_at)} for d in app.deficiencies]
    return out
