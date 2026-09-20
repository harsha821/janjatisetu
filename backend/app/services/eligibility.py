"""Rules-based multi-scheme eligibility and scholarship-conflict check.

Pure functions, no I/O. Scheme rules are data (data/schemes.json -> DB), so the
Ministry can change thresholds without a code release.

Outcomes per scheme:
  ELIGIBLE      every rule passes and no conflicting scholarship is held
  NOT_ELIGIBLE  at least one rule definitely fails
  NEEDS_REVIEW  nothing fails, but data is missing or a conflict exists.
                These go to an authorised reviewer; they are never auto-rejected.
"""
from datetime import date
from typing import Iterable

_OPS = {
    "eq": lambda a, b: a == b,
    "in": lambda a, b: a in b,
    "lte": lambda a, b: a <= b,
    "gte": lambda a, b: a >= b,
    "truthy": lambda a, b: bool(a),
}


def derive_fields(profile: dict, today: date | None = None) -> dict:
    """Adds computed fields (currently `age`) used by scheme rules."""
    p = dict(profile)
    dob = p.get("dob")
    if isinstance(dob, str) and dob:
        try:
            dob = date.fromisoformat(dob)
        except ValueError:
            dob = None
    if isinstance(dob, date):
        t = today or date.today()
        p["age"] = t.year - dob.year - ((t.month, t.day) < (dob.month, dob.day))
    return p


def check_rule(rule: dict, profile: dict) -> dict:
    actual = profile.get(rule["field"])
    out = {
        "id": rule["id"],
        "label": rule["label"],
        "field": rule["field"],
        "expected": rule.get("value"),
        "actual": actual,
    }
    if actual is None or actual == "":
        return {**out, "status": "unknown"}
    try:
        ok = _OPS[rule["op"]](actual, rule["value"])
    except TypeError:  # e.g. text where a number is expected
        return {**out, "status": "unknown"}
    return {**out, "status": "pass" if ok else "fail"}


def evaluate_scheme(
    profile: dict,
    scheme: dict,
    active_codes: Iterable[str] = (),
    all_schemes: dict[str, dict] | None = None,
) -> dict:
    p = derive_fields(profile)
    rules = [check_rule(r, p) for r in scheme["rules"]]
    fails = [r for r in rules if r["status"] == "fail"]
    unknown = [r for r in rules if r["status"] == "unknown"]

    code = scheme["code"]
    conflicts = []
    for held in set(active_codes):
        if held == code:
            continue  # holding the same scheme is a renewal, not a conflict
        other = (all_schemes or {}).get(held, {})
        if held in scheme.get("conflicts_with", []) or code in other.get("conflicts_with", []):
            conflicts.append(held)

    if fails:
        status = "NOT_ELIGIBLE"
        summary = "Does not meet: " + "; ".join(r["label"] for r in fails)
    elif unknown:
        status = "NEEDS_REVIEW"
        summary = "We need more details: " + ", ".join(r["field"].replace("_", " ") for r in unknown)
    elif conflicts:
        status = "NEEDS_REVIEW"
        summary = "You already hold: " + ", ".join(sorted(conflicts)) + ". A reviewer will check."
    else:
        status = "ELIGIBLE"
        summary = "You meet all the conditions."

    return {
        "scheme_code": code,
        "status": status,
        "summary": summary,
        "rules": rules,
        "conflicts": sorted(conflicts),
        "missing_fields": sorted({r["field"] for r in unknown}),
    }


def evaluate_all(profile: dict, schemes: list[dict], active_codes: Iterable[str] = ()) -> list[dict]:
    by_code = {s["code"]: s for s in schemes}
    active = list(active_codes)
    return [evaluate_scheme(profile, s, active, by_code) for s in schemes]
