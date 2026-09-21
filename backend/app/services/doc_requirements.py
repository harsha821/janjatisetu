"""Scheme-aware verification document requirements.

Pure function — no database or network I/O. Accepts the scheme code, course
level, current semester, and student category, and returns an **ordered list**
of VerificationStep dicts that describe exactly which documents the student must
produce (or doesn't need) for their specific combination.

The result is consumed by two API endpoints:
  • GET /api/v1/applications/{app_id}/verification-checklist
  • GET /api/v1/verification-requirements?scheme_code=…&course_level=…&semester=…

Step shape
----------
{
  "id":         str,   # unique step key, e.g. "ST_CERT"
  "label":      str,   # human-readable name
  "purpose":    str,   # one-sentence explanation
  "source":     str,   # which backend checks it: EDISTRICT | APAAR | UDISE | AISHE | UIDAI
  "doc_type":   str,   # matching Document.doc_type stored in the wallet
  "required":   bool,  # True = mandatory; False = "where applicable" / optional
  "applicable": bool,  # rule result — False = skip this step (N/A for this combination)
}
"""
from __future__ import annotations

from typing import TypedDict


class VerificationStep(TypedDict):
    id: str
    label: str
    purpose: str
    source: str
    doc_type: str
    required: bool
    applicable: bool


# ------------------------------------------------------------------ constants
# Scheme codes that use a school-level enrolment check (UDISE rather than AISHE)
_SCHOOL_SCHEMES = {"PRE_MATRIC"}

# School-level course_level values (PRE_MATRIC, and school stages in POST_MATRIC)
_SCHOOL_LEVELS = {"CLASS_9", "CLASS_10", "CLASS_11", "CLASS_12"}
_COLLEGE_LEVELS = {"DIPLOMA", "UG", "PG", "MPHIL", "PHD"}

# Scheme codes where APAAR is applicable
_APAAR_SCHEMES = {"PRE_MATRIC", "POST_MATRIC", "TOP_CLASS", "NOS", "NFST"}

# Scheme codes where income certificate is required
_INCOME_CERT_SCHEMES = {"PRE_MATRIC", "POST_MATRIC", "TOP_CLASS", "NOS"}


def _is_school(course_level: str) -> bool:
    return course_level.upper() in _SCHOOL_LEVELS


def _is_college(course_level: str) -> bool:
    return course_level.upper() in _COLLEGE_LEVELS


# ------------------------------------------------------------------ main API
def required_steps(
    scheme_code: str,
    course_level: str,
    semester: int | None = None,
    category: str = "ST",
) -> list[VerificationStep]:
    """Return the ordered verification step list for the given combination.

    Parameters
    ----------
    scheme_code:
        Scheme code string, e.g. ``"PRE_MATRIC"``, ``"POST_MATRIC"``.
    course_level:
        Student's course level, e.g. ``"CLASS_10"``, ``"UG"``, ``"PHD"``.
    semester:
        1-based semester number, or ``None`` (treated as 1 — first semester).
    category:
        Student's reservation category. Currently only ``"ST"`` is handled,
        but the parameter is accepted to allow future SC / OBC branching.
    """
    level = (course_level or "").upper()
    code = (scheme_code or "").upper()
    sem = semester if semester is not None else 1

    is_school = _is_school(level)
    is_college = _is_college(level)
    is_class10 = level == "CLASS_10"
    is_class12 = level == "CLASS_12"

    steps: list[VerificationStep] = []

    # ------------------------------------------------------------------
    # 1. ST Certificate (always required for ST schemes)
    # ------------------------------------------------------------------
    steps.append(VerificationStep(
        id="ST_CERT",
        label="ST / Caste Certificate",
        purpose="Confirm Scheduled Tribe status and tribe name via e-District",
        source="EDISTRICT",
        doc_type="CASTE_CERT",
        required=True,
        applicable=True,
    ))

    # ------------------------------------------------------------------
    # 2. APAAR Academic Account
    # ------------------------------------------------------------------
    apaar_applicable = code in _APAAR_SCHEMES
    steps.append(VerificationStep(
        id="APAAR",
        label="APAAR Academic Account",
        purpose="Link your Academic Bank of Credits and enrolment history",
        source="APAAR",
        doc_type="MARKSHEET",  # closest wallet doc; APAAR is checked via apaar_id
        required=True,
        applicable=apaar_applicable,
    ))

    # ------------------------------------------------------------------
    # 3. UDISE+ School Verification (school students only)
    # ------------------------------------------------------------------
    udise_applicable = is_school and code in _SCHOOL_SCHEMES | {"POST_MATRIC"}
    steps.append(VerificationStep(
        id="UDISE",
        label="UDISE+ School Enrolment",
        purpose="Verify your school enrolment and institution details",
        source="UDISE",
        doc_type="ENROLLMENT_CERT",
        required=True,
        applicable=udise_applicable,
    ))

    # ------------------------------------------------------------------
    # 4. AISHE College Enrolment (college students only)
    # ------------------------------------------------------------------
    aishe_applicable = is_college
    steps.append(VerificationStep(
        id="AISHE",
        label="AISHE College / University Enrolment",
        purpose="Verify college/university enrolment via AISHE directory",
        source="AISHE",
        doc_type="ENROLLMENT_CERT",
        required=True,
        applicable=aishe_applicable,
    ))

    # ------------------------------------------------------------------
    # 5. Income Certificate
    # ------------------------------------------------------------------
    income_applicable = code in _INCOME_CERT_SCHEMES
    steps.append(VerificationStep(
        id="INCOME_CERT",
        label="Income Certificate",
        purpose="Confirm annual family income is within the scheme's limit",
        source="EDISTRICT",
        doc_type="INCOME_CERT",
        required=True,
        applicable=income_applicable,
    ))

    # ------------------------------------------------------------------
    # 6. Domicile Certificate (optional / where applicable)
    # ------------------------------------------------------------------
    steps.append(VerificationStep(
        id="DOMICILE_CERT",
        label="Domicile / Residence Certificate",
        purpose="Confirm state domicile where required by the issuing state",
        source="EDISTRICT",
        doc_type="DOMICILE_CERT",
        required=False,   # shown as optional — student may or may not need it
        applicable=True,
    ))

    # ------------------------------------------------------------------
    # 7. 10th Marksheet / Board Certificate
    #   • PRE_MATRIC: Class 10 students only (not Class 9)
    #   • POST_MATRIC + college: always required
    #   • POST_MATRIC + Class 11/12: always required
    # ------------------------------------------------------------------
    if code == "PRE_MATRIC":
        tenth_applicable = is_class10
    else:
        tenth_applicable = is_college or is_school  # covers Class 11 / 12 / college

    steps.append(VerificationStep(
        id="TENTH_MARKSHEET",
        label="Class 10 Marksheet",
        purpose="Proof of passing Class 10 / Secondary board examination",
        source="EDISTRICT",
        doc_type="TENTH_MARKSHEET",
        required=True,
        applicable=tenth_applicable,
    ))

    # ------------------------------------------------------------------
    # 8. 12th Marksheet / Senior Secondary Certificate
    #   • Class 12 students (POST_MATRIC): applicable
    #   • College students (DIPLOMA / UG / PG / …): always required
    # ------------------------------------------------------------------
    twelfth_applicable = is_class12 or is_college
    steps.append(VerificationStep(
        id="TWELFTH_MARKSHEET",
        label="Class 12 Marksheet",
        purpose="Proof of passing Class 12 / Senior Secondary board examination",
        source="EDISTRICT",
        doc_type="TWELFTH_MARKSHEET",
        required=True,
        applicable=twelfth_applicable,
    ))

    # ------------------------------------------------------------------
    # 9. University / Semester Marksheet (college only, semester ≥ 2)
    # ------------------------------------------------------------------
    uni_applicable = is_college and sem >= 2
    steps.append(VerificationStep(
        id="UNIVERSITY_MARKSHEET",
        label="University / Semester Marksheet",
        purpose="Most recent semester result from your college or university",
        source="AISHE",
        doc_type="UNIVERSITY_MARKSHEET",
        required=True,
        applicable=uni_applicable,
    ))

    return steps
