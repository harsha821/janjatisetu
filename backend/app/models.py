from datetime import date, datetime, timezone
from typing import Optional

from sqlalchemy import ForeignKey, Index, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


# ============================ identity & profile ==============================
class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    phone: Mapped[str] = mapped_column(String(15), unique=True, index=True)
    email: Mapped[Optional[str]] = mapped_column(String(120), unique=True)
    password_hash: Mapped[str] = mapped_column(String(100))
    full_name: Mapped[str] = mapped_column(String(120))
    role: Mapped[str] = mapped_column(String(20), default="STUDENT")  # STUDENT | VERIFIER | ADMIN
    language: Mapped[str] = mapped_column(String(5), default="en")
    fcm_token: Mapped[Optional[str]] = mapped_column(String(300))
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    profile: Mapped[Optional["StudentProfile"]] = relationship(back_populates="user", uselist=False)
    # DigiLocker sandbox OAuth — token stored encrypted (Fernet), cleared on revoke
    digilocker_token: Mapped[Optional[str]] = mapped_column(Text)        # encrypted access token
    digilocker_token_expiry: Mapped[Optional[datetime]] = mapped_column()  # UTC expiry
    digilocker_state: Mapped[Optional[str]] = mapped_column(String(64))  # CSRF state param


class StudentProfile(Base):
    """Reusable student profile: the single source used to pre-fill every scheme."""

    __tablename__ = "student_profiles"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), unique=True)
    user: Mapped[User] = relationship(back_populates="profile")

    dob: Mapped[Optional[date]]
    gender: Mapped[Optional[str]] = mapped_column(String(1))
    category: Mapped[str] = mapped_column(String(10), default="ST")
    tribe_name: Mapped[Optional[str]] = mapped_column(String(80))
    is_pvtg: Mapped[bool] = mapped_column(default=False)
    state: Mapped[Optional[str]] = mapped_column(String(50), index=True)
    district: Mapped[Optional[str]] = mapped_column(String(60), index=True)
    lat: Mapped[Optional[float]]
    lon: Mapped[Optional[float]]

    course_level: Mapped[Optional[str]] = mapped_column(String(12))
    course_name: Mapped[Optional[str]] = mapped_column(String(100))
    institution_name: Mapped[Optional[str]] = mapped_column(String(150))
    institution_code: Mapped[Optional[str]] = mapped_column(String(20))
    institution_top_class_notified: Mapped[bool] = mapped_column(default=False)
    last_exam_percentage: Mapped[Optional[float]]
    apaar_id: Mapped[Optional[str]] = mapped_column(String(12), index=True)
    semester: Mapped[Optional[int]]  # 1-based; None = unknown; used by verification checklist

    aadhaar_hash: Mapped[Optional[str]] = mapped_column(String(64), index=True)  # never the raw number
    aadhaar_last4: Mapped[Optional[str]] = mapped_column(String(4))
    annual_family_income: Mapped[Optional[int]]
    bank_account_enc: Mapped[Optional[str]] = mapped_column(Text)  # Fernet-encrypted
    bank_account_hash: Mapped[Optional[str]] = mapped_column(String(64), index=True)
    bank_account_last4: Mapped[Optional[str]] = mapped_column(String(4))
    ifsc: Mapped[Optional[str]] = mapped_column(String(11))

    ugc_nta_qualified: Mapped[bool] = mapped_column(default=False)
    ugc_nta_roll: Mapped[Optional[str]] = mapped_column(String(30))
    foreign_admission: Mapped[bool] = mapped_column(default=False)
    active_scholarships: Mapped[list] = mapped_column(default=list)  # codes held outside this platform

    verification_status: Mapped[str] = mapped_column(String(15), default="NOT_VERIFIED")
    verification_confidence: Mapped[Optional[float]]
    verification_report: Mapped[Optional[dict]]
    verified_at: Mapped[Optional[datetime]]
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)


class Consent(Base):
    __tablename__ = "consents"
    __table_args__ = (UniqueConstraint("user_id", "purpose"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    purpose: Mapped[str] = mapped_column(String(20))  # DIGILOCKER, UIDAI, APAAR, ENROLMENT, EDISTRICT, UGC_NTA
    granted: Mapped[bool] = mapped_column(default=False)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)


# ============================== document wallet ===============================
class Document(Base):
    __tablename__ = "documents"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    doc_type: Mapped[str] = mapped_column(String(20))
    source: Mapped[str] = mapped_column(String(12))  # DIGILOCKER | UPLOAD
    uri: Mapped[Optional[str]] = mapped_column(String(200))
    file_name: Mapped[Optional[str]] = mapped_column(String(200))
    file_path: Mapped[Optional[str]] = mapped_column(String(300))
    sha256: Mapped[Optional[str]] = mapped_column(String(64), index=True)
    issuer: Mapped[Optional[str]] = mapped_column(String(150))
    doc_number: Mapped[Optional[str]] = mapped_column(String(60))
    issued_on: Mapped[Optional[date]]
    extracted: Mapped[dict] = mapped_column(default=dict)
    verified: Mapped[bool] = mapped_column(default=False)  # True when issuer-verified (DigiLocker)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


# =============================== schemes & applications ========================
class Scheme(Base):
    __tablename__ = "schemes"
    code: Mapped[str] = mapped_column(String(20), primary_key=True)
    name: Mapped[str] = mapped_column(String(150))
    short_name: Mapped[str] = mapped_column(String(30))
    portal: Mapped[str] = mapped_column(String(10))  # NSP/OTR | SFMP | NOS
    description: Mapped[str] = mapped_column(Text)
    documents: Mapped[list] = mapped_column(default=list)
    rules: Mapped[list] = mapped_column(default=list)
    conflicts_with: Mapped[list] = mapped_column(default=list)
    active: Mapped[bool] = mapped_column(default=True)


class Application(Base):
    __tablename__ = "applications"
    __table_args__ = (UniqueConstraint("user_id", "scheme_code", "academic_year"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    scheme_code: Mapped[str] = mapped_column(ForeignKey("schemes.code"))
    academic_year: Mapped[str] = mapped_column(String(9), default="2026-27")
    status: Mapped[str] = mapped_column(String(20), default="DRAFT", index=True)
    form_data: Mapped[dict] = mapped_column(default=dict)
    document_ids: Mapped[list] = mapped_column(default=list)
    external_ref: Mapped[Optional[str]] = mapped_column(String(40))
    portal_sync: Mapped[str] = mapped_column(String(15), default="NOT_SENT")  # NOT_SENT | SENT | PENDING_PUSH
    client_uuid: Mapped[Optional[str]] = mapped_column(String(40), unique=True)  # offline idempotency
    version: Mapped[int] = mapped_column(default=1)
    sanctioned_amount: Mapped[Optional[float]]
    paid_amount: Mapped[Optional[float]]
    utr: Mapped[Optional[str]] = mapped_column(String(30))
    submitted_at: Mapped[Optional[datetime]]
    auto_verified: Mapped[bool] = mapped_column(default=False)
    verification_report: Mapped[Optional[dict]] = mapped_column(default=None)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow, index=True)
    events: Mapped[list["ApplicationEvent"]] = relationship(
        back_populates="application", order_by="ApplicationEvent.id", cascade="all, delete-orphan"
    )
    deficiencies: Mapped[list["Deficiency"]] = relationship(
        back_populates="application", order_by="Deficiency.id", cascade="all, delete-orphan"
    )


class ApplicationEvent(Base):
    __tablename__ = "application_events"
    id: Mapped[int] = mapped_column(primary_key=True)
    application_id: Mapped[int] = mapped_column(ForeignKey("applications.id"), index=True)
    application: Mapped[Application] = relationship(back_populates="events")
    stage: Mapped[str] = mapped_column(String(15))  # APPLICATION|VERIFICATION|DEFICIENCY|SANCTION|DBT
    status: Mapped[str] = mapped_column(String(20))
    note: Mapped[Optional[str]] = mapped_column(Text)
    actor_role: Mapped[str] = mapped_column(String(12), default="SYSTEM")
    amount: Mapped[Optional[float]]
    reference: Mapped[Optional[str]] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class Deficiency(Base):
    __tablename__ = "deficiencies"
    id: Mapped[int] = mapped_column(primary_key=True)
    application_id: Mapped[int] = mapped_column(ForeignKey("applications.id"), index=True)
    application: Mapped[Application] = relationship(back_populates="deficiencies")
    message: Mapped[str] = mapped_column(Text)
    doc_type: Mapped[Optional[str]] = mapped_column(String(20))
    resolved: Mapped[bool] = mapped_column(default=False)
    resolution_note: Mapped[Optional[str]] = mapped_column(Text)
    raised_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    resolved_at: Mapped[Optional[datetime]]


# ============================ operations & governance ==========================
class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(120))
    body: Mapped[str] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(String(15), default="INFO")  # STATUS|DEFICIENCY|PAYMENT|OUTREACH|INFO
    data: Mapped[dict] = mapped_column(default=dict)
    is_read: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


class ExceptionCase(Base):
    """Reviewable exception: mismatch, unavailable source, anomaly, conflict. Never an auto-rejection."""

    __tablename__ = "exception_cases"
    id: Mapped[int] = mapped_column(primary_key=True)
    kind: Mapped[str] = mapped_column(String(25), index=True)
    # DATA_MISMATCH | SOURCE_UNAVAILABLE | ANOMALY | ELIGIBILITY_REVIEW | SCHEME_CONFLICT | RECORD_MATCH_UNCERTAIN | PORTAL_PUSH_FAILED
    severity: Mapped[str] = mapped_column(String(8), default="MEDIUM")
    user_id: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"), index=True)
    application_id: Mapped[Optional[int]] = mapped_column(ForeignKey("applications.id"))
    title: Mapped[str] = mapped_column(String(200))
    details: Mapped[dict] = mapped_column(default=dict)
    status: Mapped[str] = mapped_column(String(12), default="OPEN", index=True)  # OPEN|RESOLVED|DISMISSED|ESCALATED
    resolution_note: Mapped[Optional[str]] = mapped_column(Text)
    resolved_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    resolved_at: Mapped[Optional[datetime]]


class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    actor_id: Mapped[Optional[int]] = mapped_column(index=True)
    actor_role: Mapped[Optional[str]] = mapped_column(String(12))
    action: Mapped[str] = mapped_column(String(40))
    entity: Mapped[str] = mapped_column(String(30))
    entity_id: Mapped[Optional[str]] = mapped_column(String(40))
    meta: Mapped[dict] = mapped_column(default=dict)
    created_at: Mapped[datetime] = mapped_column(default=utcnow, index=True)


class SyncReceipt(Base):
    """Makes offline sync idempotent: a replayed operation returns its stored result."""

    __tablename__ = "sync_receipts"
    op_id: Mapped[str] = mapped_column(String(50), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    result: Mapped[dict] = mapped_column(default=dict)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)


# =================== external systems (mock-mode data stores) ==================
class ExternalRegistry(Base):
    """Keyed lookups answered by government sources in mock mode (UIDAI, e-District, AISHE ...)."""

    __tablename__ = "external_registry"
    __table_args__ = (UniqueConstraint("source", "key"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(15))
    key: Mapped[str] = mapped_column(String(80))
    payload: Mapped[dict] = mapped_column(default=dict)


class SourceStudentRecord(Base):
    """Population-level enrolment record from UDISE+ / APAAR / AISHE (ministry side)."""

    __tablename__ = "source_student_records"
    id: Mapped[int] = mapped_column(primary_key=True)
    source: Mapped[str] = mapped_column(String(10))  # UDISE_PLUS | APAAR | AISHE
    apaar_id: Mapped[Optional[str]] = mapped_column(String(12), index=True)
    name: Mapped[str] = mapped_column(String(120))
    dob: Mapped[Optional[date]]
    gender: Mapped[Optional[str]] = mapped_column(String(1))
    category: Mapped[str] = mapped_column(String(10), default="ST")
    state: Mapped[str] = mapped_column(String(50), index=True)
    district: Mapped[str] = mapped_column(String(60), index=True)
    institution_name: Mapped[Optional[str]] = mapped_column(String(150))
    class_level: Mapped[Optional[str]] = mapped_column(String(12))
    mobile: Mapped[Optional[str]] = mapped_column(String(15))
    lat: Mapped[Optional[float]]
    lon: Mapped[Optional[float]]
    # written by the coverage-gap run
    match_state: Mapped[str] = mapped_column(String(10), default="UNCHECKED", index=True)  # UNCHECKED|COVERED|UNCERTAIN|NO_MATCH
    match_score: Mapped[Optional[float]]
    matched_record_id: Mapped[Optional[int]]


class ScholarshipRecord(Base):
    """Scholarship record from NSP/OTR, SFMP or NOS (ministry side)."""

    __tablename__ = "scholarship_records"
    id: Mapped[int] = mapped_column(primary_key=True)
    portal: Mapped[str] = mapped_column(String(10))
    scheme_code: Mapped[str] = mapped_column(String(20))
    apaar_id: Mapped[Optional[str]] = mapped_column(String(12), index=True)
    name: Mapped[str] = mapped_column(String(120))
    dob: Mapped[Optional[date]]
    gender: Mapped[Optional[str]] = mapped_column(String(1))
    state: Mapped[Optional[str]] = mapped_column(String(50))
    district: Mapped[Optional[str]] = mapped_column(String(60))
    institution_name: Mapped[Optional[str]] = mapped_column(String(150))
    academic_year: Mapped[str] = mapped_column(String(9), default="2026-27")
    status: Mapped[str] = mapped_column(String(20), default="SUBMITTED")
    external_ref: Mapped[Optional[str]] = mapped_column(String(40), index=True)


class CoverageGap(Base):
    __tablename__ = "coverage_gaps"
    __table_args__ = (Index("ix_gap_state", "state"),)
    id: Mapped[int] = mapped_column(primary_key=True)
    source_record_id: Mapped[int] = mapped_column(ForeignKey("source_student_records.id"), unique=True)
    source_record: Mapped[SourceStudentRecord] = relationship()
    state: Mapped[str] = mapped_column(String(16), default="POTENTIAL_GAP")
    # POTENTIAL_GAP -> VALIDATED (potential unreached student) -> OUTREACH_SENT -> APPLIED  |  DISMISSED
    reason: Mapped[Optional[str]] = mapped_column(Text)
    possible_schemes: Mapped[list] = mapped_column(default=list)
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(default=utcnow, onupdate=utcnow)


class Outreach(Base):
    __tablename__ = "outreach"
    id: Mapped[int] = mapped_column(primary_key=True)
    gap_id: Mapped[int] = mapped_column(ForeignKey("coverage_gaps.id"), index=True)
    channel: Mapped[str] = mapped_column(String(12))  # JAGO | SMS | APP | INSTITUTION
    message: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(12), default="SENT")
    sent_by: Mapped[Optional[int]] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(default=utcnow)
