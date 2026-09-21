"""Cross-source verification: checks a student's profile against UIDAI (identity),
State e-District (caste + income certificates), APAAR (academic account),
UDISE+ / AISHE (institution enrolment), and UGC-NTA (qualification).

Each source is only called if the student has granted consent for it (NO_CONSENT
otherwise — never a silent skip that looks like a pass). A source that raises
SourceUnavailable is reported, not propagated, so an outage becomes a reviewable
exception rather than a failed request. A mismatch never rejects on its own;
it is surfaced for a reviewer or routed to manual check.
"""
from typing import Any

from ..integrations.gateway import SourceUnavailable
from .matching import dob_similarity, name_similarity

INCOME_TOLERANCE = 0.15  # certificates and self-reported income may legitimately differ a little


def _uidai_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "UIDAI", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "No UIDAI record found for this Aadhaar"}
    name_s = name_similarity(profile.get("full_name"), resp.get("name"))
    dob_s = dob_similarity(profile.get("dob"), resp.get("dob"))
    ga, gb = (profile.get("gender") or "").upper()[:1], (resp.get("gender") or "").upper()[:1]
    gender_s = 1.0 if (ga and gb and ga == gb) else (0.0 if ga and gb else None)
    comps = {k: round(v, 3) for k, v in {"name": name_s, "dob": dob_s, "gender": gender_s}.items() if v is not None}
    score = sum(comps.values()) / len(comps) if comps else 0.0
    status = "MATCH" if score >= 0.85 else "REVIEW" if score >= 0.6 else "MISMATCH"
    return {"source": "UIDAI", "status": status, "score": round(score, 3), "components": comps}


def _edistrict_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "EDISTRICT", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "No e-District certificates found"}
    caste, income = resp.get("caste") or {}, resp.get("income") or {}
    cat_ok = (caste.get("category") == profile.get("category")) if caste.get("category") else None
    tribe_ok = None
    if caste.get("tribe") and profile.get("tribe_name"):
        tribe_ok = (name_similarity(caste["tribe"], profile["tribe_name"]) or 0) >= 0.85
    cert_income, prof_income = income.get("amount"), profile.get("annual_family_income")
    income_ok = None
    if cert_income is not None and prof_income is not None:
        base = max(cert_income, prof_income, 1)
        income_ok = abs(cert_income - prof_income) / base <= INCOME_TOLERANCE

    known = [v for v in (cat_ok, tribe_ok, income_ok) if v is not None]
    comps = {"category": cat_ok, "tribe": tribe_ok, "income": income_ok}
    if known and all(known):
        return {"source": "EDISTRICT", "status": "MATCH", "score": 1.0, "components": comps}
    return {"source": "EDISTRICT", "status": "REVIEW", "score": 0.5, "components": comps}


def _apaar_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "APAAR", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "No APAAR record found for this student"}
    name_s = name_similarity(profile.get("full_name"), resp.get("name"))
    dob_s = dob_similarity(profile.get("dob"), resp.get("dob"))
    inst_s = (name_similarity(profile.get("institution_name"), resp.get("institution_name"))
              if (profile.get("institution_name") and resp.get("institution_name")) else None)
    comps = {k: round(v, 3) for k, v in {"name": name_s, "dob": dob_s, "institution": inst_s}.items() if v is not None}
    score = sum(comps.values()) / len(comps) if comps else 0.0
    status = "MATCH" if score >= 0.80 else "REVIEW" if score >= 0.55 else "MISMATCH"
    return {"source": "APAAR", "status": status, "score": round(score, 3), "components": comps}


def _udise_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "UDISE", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "School code not found in UDISE+ registry"}
    inst_s = (name_similarity(profile.get("institution_name"), resp.get("name"))
              if (profile.get("institution_name") and resp.get("name")) else 1.0)
    comps = {"institution_code": True, "institution_name": round(inst_s, 3) if inst_s is not None else 1.0}
    score = inst_s if inst_s is not None else 1.0
    status = "MATCH" if score >= 0.70 else "REVIEW"
    return {"source": "UDISE", "status": status, "score": round(score, 3), "components": comps}


def _aishe_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "AISHE", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "Institution code not found in AISHE directory"}
    inst_s = (name_similarity(profile.get("institution_name"), resp.get("name"))
              if (profile.get("institution_name") and resp.get("name")) else 1.0)
    top_class = resp.get("top_class_notified")
    comps = {"institution_code": True, "institution_name": round(inst_s, 3) if inst_s is not None else 1.0}
    if profile.get("scheme_code") == "TOP_CLASS" and top_class is False:
        return {"source": "AISHE", "status": "REVIEW", "score": 0.5, "components": comps,
                "note": "Institution is not recognized as notified Top Class institution in AISHE"}
    score = inst_s if inst_s is not None else 1.0
    status = "MATCH" if score >= 0.70 else "REVIEW"
    return {"source": "AISHE", "status": status, "score": round(score, 3), "components": comps}


def _ugc_nta_check(profile: dict, resp: dict) -> dict:
    if not resp.get("found"):
        return {"source": "UGC_NTA", "status": "REVIEW", "score": 0.0, "components": {},
                "note": "Roll number not found in UGC-NTA qualification database"}
    qualified = bool(resp.get("qualified"))
    name_s = (name_similarity(profile.get("full_name"), resp.get("name"))
              if (profile.get("full_name") and resp.get("name")) else None)
    comps = {"qualified": qualified}
    if name_s is not None:
        comps["name"] = round(name_s, 3)
    if qualified and (name_s is None or name_s >= 0.75):
        return {"source": "UGC_NTA", "status": "MATCH", "score": 1.0, "components": comps}
    return {"source": "UGC_NTA", "status": "REVIEW" if qualified else "MISMATCH",
            "score": 0.4 if qualified else 0.0, "components": comps,
            "note": "UGC-NTA qualification or candidate name mismatch"}


def _has_consent(source: str, consents: set[str]) -> bool:
    if source in consents:
        return True
    if source in ("UDISE", "AISHE") and "ENROLMENT" in consents:
        return True
    return False


def _determine_sources(profile: dict, consents: set[str], scheme_code: str | None = None) -> list[tuple[str, str, str, Any]]:
    sources: list[tuple[str, str, str, Any]] = []
    # Identity: UIDAI
    if profile.get("aadhaar_hash") or "UIDAI" in consents:
        sources.append(("UIDAI", "verify_identity", "aadhaar_hash", _uidai_check))
    # Certificates: EDISTRICT
    if profile.get("aadhaar_hash") or "EDISTRICT" in consents:
        sources.append(("EDISTRICT", "certificates", "aadhaar_hash", _edistrict_check))
    # Academic Bank: APAAR
    if profile.get("apaar_id") or "APAAR" in consents:
        sources.append(("APAAR", "lookup", "apaar_id", _apaar_check))
    # Enrolment / Institution: UDISE+ for School, AISHE for Higher Education
    level = (profile.get("course_level") or "").upper()
    is_school = level.startswith("CLASS")
    if is_school:
        if profile.get("institution_code") or _has_consent("UDISE", consents):
            sources.append(("UDISE", "institution", "institution_code", _udise_check))
    else:
        if profile.get("institution_code") or _has_consent("AISHE", consents):
            sources.append(("AISHE", "institution", "institution_code", _aishe_check))
    # Qualification: UGC_NTA
    s_code = scheme_code or profile.get("scheme_code")
    if profile.get("ugc_nta_roll") or profile.get("ugc_nta_qualified") or s_code == "NFST" or "UGC_NTA" in consents:
        param = "ugc_nta_roll" if profile.get("ugc_nta_roll") else "roll"
        sources.append(("UGC_NTA", "qualification", param, _ugc_nta_check))
    return sources


def run_verification(profile: dict, gateway, consents: set[str], scheme_code: str | None = None) -> dict:
    checks: list[dict] = []
    unavailable: list[str] = []
    sources = _determine_sources(profile, consents, scheme_code)

    for source, op, param, checker in sources:
        if not _has_consent(source, consents):
            checks.append({"source": source, "status": "NO_CONSENT", "score": None, "components": {}})
            continue
        try:
            val = profile.get(param) or profile.get("roll") or profile.get("ugc_nta_roll")
            resp = gateway.call(source, op, **{param: val})
        except SourceUnavailable:
            unavailable.append(source)
            continue
        checks.append(checker(profile, resp))

    scored = [c["score"] for c in checks if c["score"] is not None]
    confidence = round(sum(scored) / len(scored), 3) if scored else None
    mismatches = [c["source"] for c in checks if c["status"] in ("MISMATCH", "REVIEW")]

    # Check whether all applicable sources satisfied verification
    all_matched = bool(checks and all(c["status"] == "MATCH" for c in checks) and not unavailable)
    all_satisfy = bool(all_matched and (confidence is not None and confidence >= 0.85) and not mismatches)

    if mismatches:
        status = "NEEDS_REVIEW"
    elif unavailable and any(c["status"] == "MATCH" for c in checks):
        status = "PARTIAL"
    elif unavailable and not checks:
        status = "PARTIAL"
    elif all_matched:
        status = "VERIFIED"
    elif checks and all(c["status"] == "NO_CONSENT" for c in checks):
        status = "NOT_VERIFIED"
    else:
        status = "NOT_VERIFIED"

    return {
        "checks": checks,
        "confidence": confidence,
        "mismatches": mismatches,
        "unavailable": unavailable,
        "status": status,
        "all_satisfy": all_satisfy,
    }

