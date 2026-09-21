from datetime import date
from typing import Literal, Optional

from pydantic import BaseModel, Field

DOC_TYPES = Literal["CASTE_CERT", "INCOME_CERT", "MARKSHEET", "BANK_PASSBOOK", "ADMISSION_LETTER", "NET_JRF_CERT"]


# ------------------------------------------------------------------- auth
class RegisterIn(BaseModel):
    phone: str = Field(min_length=10, max_length=15)
    password: str = Field(min_length=8, max_length=100)
    full_name: str = Field(min_length=2, max_length=120)
    email: Optional[str] = None
    language: str = "en"


# ---------------------------------------------------------------- profile
class ProfileIn(BaseModel):
    dob: Optional[date] = None
    gender: Optional[str] = None
    category: Optional[str] = None
    tribe_name: Optional[str] = None
    is_pvtg: Optional[bool] = None
    state: Optional[str] = None
    district: Optional[str] = None
    lat: Optional[float] = None
    lon: Optional[float] = None

    course_level: Optional[str] = None
    course_name: Optional[str] = None
    institution_name: Optional[str] = None
    institution_code: Optional[str] = None
    institution_top_class_notified: Optional[bool] = None
    last_exam_percentage: Optional[float] = None
    apaar_id: Optional[str] = None

    annual_family_income: Optional[int] = None
    ifsc: Optional[str] = None
    ugc_nta_qualified: Optional[bool] = None
    ugc_nta_roll: Optional[str] = None
    foreign_admission: Optional[bool] = None

    # Raw plaintext, never persisted as-is: the profile router hashes/encrypts these
    # and they are stripped before any generic field-by-field update (see sync.py).
    aadhaar_number: Optional[str] = None
    bank_account_number: Optional[str] = None


class ConsentIn(BaseModel):
    purpose: str
    granted: bool = True


class LanguageIn(BaseModel):
    language: str = Field(pattern="^(en|hi)$")


class FcmTokenIn(BaseModel):
    token: str


# ------------------------------------------------------------------ wallet
class WalletImportIn(BaseModel):
    uri: str


class DigiLockerFetchIn(BaseModel):
    doc_type: DOC_TYPES
    doc_number: str
    issuer: Optional[str] = "DigiLocker National Registry"


class UseDocIn(BaseModel):
    application_id: int


# -------------------------------------------------------------- applications
class ApplicationCreateIn(BaseModel):
    scheme_code: str
    academic_year: str = "2026-27"
    client_uuid: Optional[str] = None


class ApplicationUpdateIn(BaseModel):
    form_data: Optional[dict] = None
    document_ids: Optional[list[int]] = None


class ResolveDeficiencyIn(BaseModel):
    note: str = Field(min_length=1)
    document_id: Optional[int] = None


# --------------------------------------------------------------------- sync
class SyncOp(BaseModel):
    op_id: str
    type: Literal["CREATE_APPLICATION", "UPDATE_APPLICATION", "SUBMIT_APPLICATION", "UPDATE_PROFILE"]
    application_id: Optional[int] = None
    client_uuid: Optional[str] = None
    payload: dict = Field(default_factory=dict)


class SyncPushIn(BaseModel):
    operations: list[SyncOp]


# -------------------------------------------------------------------- admin
class AdminActionIn(BaseModel):
    action: Literal["START_REVIEW", "RAISE_DEFICIENCY", "VERIFY", "SANCTION", "PAY", "REJECT", "RETRY_PUSH"]
    note: Optional[str] = None
    doc_type: Optional[str] = None
    amount: Optional[float] = None
    utr: Optional[str] = None


class ExceptionResolveIn(BaseModel):
    resolution: Literal["CONFIRMED_OK", "CORRECTED", "DISMISS", "ESCALATE"]
    note: Optional[str] = None


class OutreachIn(BaseModel):
    gap_ids: list[int]
    channel: Literal["JAGO", "SMS", "APP", "INSTITUTION"]
    message: Optional[str] = None


class GapResolveIn(BaseModel):
    action: Literal["DISMISS", "MARK_APPLIED", "REOPEN"]
    note: Optional[str] = Field(default=None, max_length=500)  # required for DISMISS


# ---------------------------------------------------------------- assistant
class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=500)
