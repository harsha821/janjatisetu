"""The full submission pipeline: document check -> eligibility gate -> portal
push -> cross-source verification -> anomaly screen.

Nothing here rejects an application. A hard gate (missing documents, a
definite NOT_ELIGIBLE) stops the *submission* before it is sent anywhere;
once submitted, every uncertainty (mismatch, outage, anomaly) becomes a
reviewable exception case instead.
"""
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..integrations.gateway import PORTAL_KEY, Gateway
from ..models import Application, Document, Scheme, StudentProfile, User, utcnow
from . import anomaly
from .cases import open_case
from .coverage_gap import mark_applied
from .student import _profile_for_rules, consent_set, eligibility_for
from .verification import run_verification
from .workflow import transition


class SubmissionError(Exception):
    def __init__(self, code: int, detail):
        self.code = code
        self.detail = detail
        super().__init__(str(detail))


def push_to_portal(db: Session, app: Application, scheme: Scheme, profile: StudentProfile, gateway: Gateway) -> bool:
    source = PORTAL_KEY.get(scheme.portal, scheme.portal)
    try:
        resp = gateway.call(source, "submit", scheme_code=app.scheme_code, academic_year=app.academic_year, form=app.form_data)
        app.external_ref = resp.get("external_ref")
        app.portal_sync = "SENT"
        return True
    except Exception:  # SourceUnavailable, or any transient failure talking to the portal
        app.portal_sync = "PENDING_PUSH"
        open_case(db, "PORTAL_PUSH_FAILED", f"Could not submit to the {source} portal", application_id=app.id,
                 user_id=app.user_id, severity="MEDIUM", details={"portal": source})
        return False


def _verification_profile(user: User, profile: StudentProfile) -> dict:
    p = _profile_for_rules(profile)
    p.update(full_name=user.full_name, gender=profile.gender, tribe_name=profile.tribe_name,
             aadhaar_hash=profile.aadhaar_hash)
    return p


def submit_application(db: Session, app: Application, user: User, profile: StudentProfile) -> None:
    scheme = db.get(Scheme, app.scheme_code)
    if scheme is None:
        raise SubmissionError(404, "Scheme not found")

    attached = {d.doc_type for d in db.scalars(select(Document).where(Document.id.in_(app.document_ids or [])))}
    missing = [dt for dt in scheme.documents if dt not in attached]
    if missing:
        raise SubmissionError(422, {"missing_documents": missing, "message": "Attach the required documents first"})

    this_scheme = next((r for r in eligibility_for(db, profile) if r["scheme_code"] == app.scheme_code), None)
    if this_scheme and this_scheme["status"] == "NOT_ELIGIBLE":
        raise SubmissionError(422, {"reason": this_scheme["summary"]})

    transition(db, app, "SUBMITTED", actor_role="STUDENT", scheme_name=scheme.short_name)
    gateway = Gateway(db)
    push_to_portal(db, app, scheme, profile, gateway)
    transition(db, app, "UNDER_VERIFICATION", note="Sent for verification", scheme_name=scheme.short_name)

    consents = consent_set(db, user.id)
    report = run_verification(_verification_profile(user, profile), gateway, consents)
    profile.verification_status = report["status"]
    profile.verification_confidence = report["confidence"]
    profile.verification_report = report
    profile.verified_at = utcnow()

    for check in report["checks"]:
        if check["status"] in ("MISMATCH", "REVIEW"):
            severity = "HIGH" if check["status"] == "MISMATCH" else "MEDIUM"
            open_case(db, "DATA_MISMATCH", f"{check['source']} data does not match the application", application_id=app.id,
                     user_id=user.id, severity=severity,
                     details={"source": check["source"], "components": check.get("components"), "score": check.get("score")})
    for source in report["unavailable"]:
        open_case(db, "SOURCE_UNAVAILABLE", f"{source} was unavailable during verification", application_id=app.id,
                 user_id=user.id, severity="LOW", details={"source": source})

    verdict = anomaly.assess(_profile_for_rules(profile), report, len(app.document_ids or []))
    if verdict["flagged"]:
        open_case(db, "ANOMALY", "Application flagged for an unusual pattern", application_id=app.id, user_id=user.id,
                 severity="MEDIUM", details={"reasons": verdict["reasons"], "score": verdict["score"]})

    mark_applied(db, profile.apaar_id)
