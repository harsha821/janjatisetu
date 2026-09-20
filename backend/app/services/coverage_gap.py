"""Ministry-side coverage-gap detection.

  UDISE+ / APAAR enrolled ST students
        -> population-level record matching against NSP/OTR + SFMP + NOS records
        -> no matching record        = POTENTIAL GAP
        -> eligibility & record validation
        -> validated                 = POTENTIAL UNREACHED STUDENT
        -> targeted outreach (JAGO / SMS / app / institution)
        -> student applies           = APPLIED

A missing scholarship record is a potential gap, NOT proof that the student is
eligible or that they chose not to apply. Uncertain matches go to reviewers.

Reviewers can also close a gap by hand (`resolve_gap`): dismiss it with a reason,
mark it applied (student applied outside JanjatiSetu), or reopen it so it is
re-validated and can be contacted again through another channel.
"""
from collections import Counter

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import (Application, CoverageGap, ExceptionCase, Outreach, ScholarshipRecord, Scheme,
                      SourceStudentRecord, StudentProfile)
from .cases import open_case
from .eligibility import evaluate_all
from .matching import Matcher
from .notify import notify, send_sms

DISCLAIMER = ("A missing scholarship record is a potential coverage gap, not proof that the student is eligible "
              "or that they chose not to apply. Every case is validated before outreach.")

DEFAULT_MESSAGE = ("Johar! Scholarships may be available for you under the Ministry of Tribal Affairs. "
                   "Open JanjatiSetu or ask JAGO to check which ones you can apply for.")


# action -> gap states it may be applied from
RESOLVE_TRANSITIONS = {
    "DISMISS": ("POTENTIAL_GAP", "VALIDATED", "OUTREACH_SENT"),
    "MARK_APPLIED": ("POTENTIAL_GAP", "VALIDATED", "OUTREACH_SENT"),
    "REOPEN": ("DISMISSED", "OUTREACH_SENT", "APPLIED"),
}


class GapError(Exception):
    """A reviewer action that isn't valid for the gap's current state."""


def _person(r) -> dict:
    return {"id": r.id, "name": r.name, "dob": r.dob, "gender": r.gender, "apaar_id": r.apaar_id,
            "state": r.state, "district": r.district, "institution_name": r.institution_name}


def run_detection(db: Session) -> dict:
    """Re-matches every enrolled ST record. Safe to run repeatedly."""
    pool = [_person(r) for r in db.scalars(select(ScholarshipRecord))]
    matcher = Matcher(pool)
    sources = list(db.scalars(select(SourceStudentRecord).where(SourceStudentRecord.category == "ST")))
    # Re-running must not pile up duplicate review cases, nor re-raise one a reviewer already decided.
    already_flagged = {c.details.get("source_record_id") for c in db.scalars(select(ExceptionCase).where(
        ExceptionCase.kind == "RECORD_MATCH_UNCERTAIN")) if c.details}

    for src in sources:
        rec, res = matcher.best(_person(src))
        src.match_score = res.score if rec else None
        src.matched_record_id = rec["id"] if rec and res.decision != "NO_MATCH" else None
        if res.decision == "MATCH":
            src.match_state = "COVERED"
        elif res.decision == "POSSIBLE":
            src.match_state = "UNCERTAIN"
            if src.id not in already_flagged:
                open_case(db, "RECORD_MATCH_UNCERTAIN", f"Possible scholarship record for {src.name} ({src.district})",
                          severity="LOW", details={"source_record_id": src.id, "matched_record_id": rec["id"], "score": res.score})
                already_flagged.add(src.id)
        else:
            src.match_state = "NO_MATCH"

    db.flush()
    existing = {g.source_record_id: g for g in db.scalars(select(CoverageGap))}
    for src in sources:
        gap = existing.get(src.id)
        if src.match_state == "NO_MATCH" and gap is None:
            db.add(CoverageGap(source_record_id=src.id, state="POTENTIAL_GAP"))
        elif src.match_state == "COVERED" and gap is not None and gap.state not in ("APPLIED", "DISMISSED"):
            gap.state, gap.reason = "APPLIED", "A scholarship record now exists"
    db.flush()
    validate_gaps(db)
    return funnel(db)


def validate_gaps(db: Session) -> None:
    schemes = [{"code": s.code, "rules": s.rules, "conflicts_with": s.conflicts_with}
               for s in db.scalars(select(Scheme).where(Scheme.active))]
    registered = {p.apaar_id: p.user_id for p in db.scalars(select(StudentProfile).where(StudentProfile.apaar_id.is_not(None)))}
    for gap in db.scalars(select(CoverageGap).where(CoverageGap.state == "POTENTIAL_GAP")):
        src = gap.source_record
        uid = registered.get(src.apaar_id)
        if uid and db.scalar(select(func.count()).select_from(Application).where(
                Application.user_id == uid, Application.status != "DRAFT")):
            gap.state, gap.reason = "DISMISSED", "An application already exists on JanjatiSetu"
            continue
        # Income and other details are unknown at population level, so a scheme is only
        # ruled out when a known fact (category, class level) definitely fails.
        results = evaluate_all({"category": src.category, "course_level": src.class_level}, schemes)
        possible = [r["scheme_code"] for r in results if r["status"] != "NOT_ELIGIBLE"]
        if possible:
            gap.state, gap.possible_schemes = "VALIDATED", possible
            gap.reason = "No scholarship record found; at least one scheme may apply. Income still to be confirmed."
        else:
            gap.state, gap.reason = "DISMISSED", "No MoTA scheme applies at this class level"


def send_outreach(db: Session, gap_ids: list[int], channel: str, message: str | None, sender_id: int) -> dict:
    """Contact validated gaps. `sent` counts cases actioned; `delivered` / `queued` / `undelivered`
    say what actually happened, so a message that could not reach anyone is never reported as delivered."""
    text = (message or DEFAULT_MESSAGE).strip()
    wanted = set(gap_ids)
    found = sent = skipped = delivered = queued = undelivered = 0
    for gap in db.scalars(select(CoverageGap).where(CoverageGap.id.in_(wanted))):
        found += 1
        if gap.state != "VALIDATED":  # never contact an unvalidated, dismissed or already-contacted case
            skipped += 1
            continue
        src = gap.source_record
        status, why = "DELIVERED", None
        if channel in ("JAGO", "APP"):
            user_id = (db.scalar(select(StudentProfile.user_id).where(StudentProfile.apaar_id == src.apaar_id))
                       if src.apaar_id else None)
            if user_id:
                notify(db, user_id, "Scholarships you may be eligible for", text, kind="OUTREACH")
            else:
                status, why = "UNDELIVERED", "the student is not registered on JanjatiSetu"
        elif channel == "SMS":
            if not src.mobile:
                status, why = "UNDELIVERED", "no mobile number on record"
            elif not send_sms(src.mobile, text):
                status, why = "UNDELIVERED", "SMS is disabled or the provider failed"
        else:  # INSTITUTION: recorded for the institution's nodal officer to act on
            status = "QUEUED"

        db.add(Outreach(gap_id=gap.id, channel=channel, message=text, status=status, sent_by=sender_id))
        gap.state = "OUTREACH_SENT"
        if status == "DELIVERED":
            gap.reason, delivered = f"Outreach delivered via {channel}", delivered + 1
        elif status == "QUEUED":
            gap.reason, queued = "Recorded for the institution's nodal officer", queued + 1
        else:
            gap.reason = f"Outreach via {channel} could not be delivered: {why}. Reopen to try another channel."
            undelivered += 1
        sent += 1
    skipped += len(wanted) - found  # unknown ids
    return {"sent": sent, "skipped": skipped, "delivered": delivered, "queued": queued, "undelivered": undelivered}


def resolve_gap(db: Session, gap: CoverageGap, action: str, note: str | None) -> CoverageGap:
    """Reviewer closes or reopens a gap. Raises GapError if the action isn't valid from the current state."""
    allowed = RESOLVE_TRANSITIONS.get(action)
    if allowed is None:
        raise GapError(f"Unknown action {action}")
    if gap.state not in allowed:
        raise GapError(f"Cannot {action.replace('_', ' ').lower()} a gap that is {gap.state}")
    note = (note or "").strip()
    if action == "DISMISS":
        if not note:
            raise GapError("A written reason is required to dismiss a gap")
        gap.state, gap.reason = "DISMISSED", f"Dismissed by reviewer: {note}"
    elif action == "MARK_APPLIED":
        gap.state, gap.reason = "APPLIED", "Confirmed applied by reviewer" + (f": {note}" if note else "")
    else:  # REOPEN: back through validation, so an outdated or wrong closure can be re-checked
        if gap.source_record.match_state == "COVERED":
            raise GapError("A scholarship record now exists for this student, so there is nothing to reopen")
        gap.state, gap.reason = "POTENTIAL_GAP", None
        db.flush()
        validate_gaps(db)
    db.flush()
    return gap


def mark_applied(db: Session, apaar_id: str | None) -> None:
    """Called when a student submits an application: closes the loop on any open gap."""
    if not apaar_id:
        return
    for gap in db.scalars(select(CoverageGap).join(SourceStudentRecord).where(
            SourceStudentRecord.apaar_id == apaar_id, CoverageGap.state.in_(("POTENTIAL_GAP", "VALIDATED", "OUTREACH_SENT")))):
        gap.state, gap.reason = "APPLIED", "Student applied through JanjatiSetu"


def funnel(db: Session) -> dict:
    def count(stmt) -> int:
        return db.scalar(stmt) or 0

    enrolled = count(select(func.count()).select_from(SourceStudentRecord).where(SourceStudentRecord.category == "ST"))
    by_match = dict(db.execute(select(SourceStudentRecord.match_state, func.count()).where(
        SourceStudentRecord.category == "ST").group_by(SourceStudentRecord.match_state)).all())
    by_gap = dict(db.execute(select(CoverageGap.state, func.count()).group_by(CoverageGap.state)).all())
    validated = sum(by_gap.get(s, 0) for s in ("VALIDATED", "OUTREACH_SENT", "APPLIED"))
    contacted = count(select(func.count(func.distinct(Outreach.gap_id))))  # gaps actually contacted, even if since closed
    return {
        "enrolled_st": enrolled,
        "matched": by_match.get("COVERED", 0),
        "uncertain": by_match.get("UNCERTAIN", 0),
        "potential_gap": by_match.get("NO_MATCH", 0),
        "validated": validated,
        "dismissed": by_gap.get("DISMISSED", 0),
        "ready_for_outreach": by_gap.get("VALIDATED", 0),
        "outreach_sent": contacted,
        "applied": by_gap.get("APPLIED", 0),
        "unchecked": by_match.get("UNCHECKED", 0),
        "note": DISCLAIMER,
    }


def by_district(db: Session, limit: int = 15) -> list[dict]:
    rows = db.execute(
        select(SourceStudentRecord.state, SourceStudentRecord.district, CoverageGap.state, func.count(),
               func.avg(SourceStudentRecord.lat), func.avg(SourceStudentRecord.lon))
        .join(CoverageGap, CoverageGap.source_record_id == SourceStudentRecord.id)
        .where(CoverageGap.state.in_(("VALIDATED", "OUTREACH_SENT", "POTENTIAL_GAP")))
        .group_by(SourceStudentRecord.state, SourceStudentRecord.district, CoverageGap.state)
    ).all()
    agg: dict[tuple, Counter] = {}
    coords: dict[tuple, tuple] = {}
    for state, district, gstate, n, lat, lon in rows:
        agg.setdefault((state, district), Counter())[gstate] += n
        coords[(state, district)] = (lat, lon)
    out = [{"state": k[0], "district": k[1], "open_gaps": sum(v.values()), "validated": v.get("VALIDATED", 0),
            "lat": coords[k][0], "lon": coords[k][1]} for k, v in agg.items()]
    return sorted(out, key=lambda d: d["open_gaps"], reverse=True)[:limit]
