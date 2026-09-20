"""Cross-source verification: checks a student's profile against UIDAI (identity)
and e-District (caste + income certificates).

Each source is only called if the student has granted consent for it (NO_CONSENT
otherwise — never a silent skip that looks like a pass). A source that raises
SourceUnavailable is reported, not propagated, so an outage becomes a reviewable
exception rather than a failed request. A mismatch never rejects on its own;
it is surfaced for a reviewer.
"""
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


_CHECKERS = {"UIDAI": ("verify_identity", "aadhaar_hash", _uidai_check),
            "EDISTRICT": ("certificates", "aadhaar_hash", _edistrict_check)}


def run_verification(profile: dict, gateway, consents: set[str]) -> dict:
    checks: list[dict] = []
    unavailable: list[str] = []

    for source, (op, param, checker) in _CHECKERS.items():
        if source not in consents:
            checks.append({"source": source, "status": "NO_CONSENT", "score": None, "components": {}})
            continue
        try:
            resp = gateway.call(source, op, **{param: profile.get(param)})
        except SourceUnavailable:
            unavailable.append(source)
            continue
        checks.append(checker(profile, resp))

    scored = [c["score"] for c in checks if c["score"] is not None]
    confidence = round(sum(scored) / len(scored), 3) if scored else None
    mismatches = [c["source"] for c in checks if c["status"] in ("MISMATCH", "REVIEW")]

    if mismatches:
        status = "NEEDS_REVIEW"
    elif unavailable and any(c["status"] == "MATCH" for c in checks):
        status = "PARTIAL"
    elif unavailable and not checks:
        status = "PARTIAL"
    elif checks and all(c["status"] == "MATCH" for c in checks) and not unavailable:
        status = "VERIFIED"
    elif checks and all(c["status"] == "NO_CONSENT" for c in checks):
        status = "NOT_VERIFIED"
    else:
        status = "NOT_VERIFIED"

    return {"checks": checks, "confidence": confidence, "mismatches": mismatches,
            "unavailable": unavailable, "status": status}
