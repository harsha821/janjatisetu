from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..integrations.gateway import Gateway
from ..models import Consent, User, utcnow
from ..schemas import ConsentIn, FcmTokenIn, LanguageIn, ProfileIn
from ..security import encrypt_field, hash_identifier
from ..services.cases import audit
from ..services.student import consent_set, get_profile, profile_out
from ..services.verification import run_verification

router = APIRouter(prefix="/profile", tags=["profile"])


def _verification_profile(user: User, p) -> dict:
    return {"full_name": user.full_name, "dob": p.dob.isoformat() if p.dob else None, "gender": p.gender,
            "category": p.category, "tribe_name": p.tribe_name, "aadhaar_hash": p.aadhaar_hash,
            "annual_family_income": p.annual_family_income, "course_level": p.course_level,
            "apaar_id": p.apaar_id, "institution_code": p.institution_code, "institution_name": p.institution_name,
            "ugc_nta_roll": p.ugc_nta_roll, "ugc_nta_qualified": p.ugc_nta_qualified}


@router.get("")
def get_my_profile(user: User = Depends(student_only), db: Session = Depends(get_db)):
    p = get_profile(db, user)
    db.commit()
    return profile_out(p)


@router.put("")
def update_profile(body: ProfileIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    p = get_profile(db, user)
    data = body.model_dump(exclude_unset=True)
    aadhaar = data.pop("aadhaar_number", None)
    bank = data.pop("bank_account_number", None)
    for k, v in data.items():
        setattr(p, k, v)
    if aadhaar:
        p.aadhaar_hash, p.aadhaar_last4 = hash_identifier(aadhaar), aadhaar[-4:]
    if bank:
        p.bank_account_enc = encrypt_field(bank)
        p.bank_account_hash, p.bank_account_last4 = hash_identifier(bank), bank[-4:]
    audit(db, user, "UPDATE_PROFILE", "profile", user.id)
    db.commit()
    return profile_out(p)


@router.get("/consents")
def list_consents(user: User = Depends(student_only), db: Session = Depends(get_db)):
    rows = db.scalars(select(Consent).where(Consent.user_id == user.id))
    return [{"purpose": c.purpose, "granted": c.granted, "updated_at": c.updated_at.isoformat()} for c in rows]


@router.put("/consents")
def set_consent(body: ConsentIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    row = db.scalar(select(Consent).where(Consent.user_id == user.id, Consent.purpose == body.purpose))
    if row is None:
        row = Consent(user_id=user.id, purpose=body.purpose, granted=body.granted)
        db.add(row)
    else:
        row.granted = body.granted
    audit(db, user, "SET_CONSENT", "consent", body.purpose, granted=body.granted)
    db.commit()
    return {"purpose": body.purpose, "granted": body.granted}


@router.post("/verify")
def verify(user: User = Depends(student_only), db: Session = Depends(get_db)):
    p = get_profile(db, user)
    report = run_verification(_verification_profile(user, p), Gateway(db), consent_set(db, user.id))
    p.verification_status = report["status"]
    p.verification_confidence = report["confidence"]
    p.verification_report = report
    p.verified_at = utcnow()
    audit(db, user, "MANUAL_VERIFY", "profile", user.id)
    db.commit()
    return report


@router.put("/language")
def set_language(body: LanguageIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    user.language = body.language
    db.commit()
    return {"language": user.language}


@router.put("/fcm-token")
def set_fcm_token(body: FcmTokenIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    user.fcm_token = body.token
    db.commit()
    return {"ok": True}
