"""Unit tests for the decision logic. No database or web framework needed."""
import json
from datetime import date
from pathlib import Path

from app.integrations.gateway import SourceUnavailable
from app.services import anomaly, assistant, eligibility as E, matching as M
from app.services.lifecycle import build_timeline, can_transition
from app.services.verification import run_verification

SCHEMES = json.loads((Path(__file__).parent.parent / "app" / "data" / "schemes.json").read_text(encoding="utf-8"))


def _status(profile, active=()):
    return {r["scheme_code"]: r for r in E.evaluate_all(profile, SCHEMES, active)}


# ------------------------------------------------------------ eligibility
def test_class_10_student_is_eligible_only_for_pre_matric():
    r = _status({"category": "ST", "course_level": "CLASS_10", "annual_family_income": 120000})
    assert r["PRE_MATRIC"]["status"] == "ELIGIBLE"
    assert r["POST_MATRIC"]["status"] == "NOT_ELIGIBLE"


def test_missing_income_routes_to_review_not_rejection():
    r = _status({"category": "ST", "course_level": "UG"})["POST_MATRIC"]
    assert r["status"] == "NEEDS_REVIEW"
    assert "annual_family_income" in r["missing_fields"]


def test_conflicting_scholarship_needs_review():
    r = _status({"category": "ST", "course_level": "PG", "annual_family_income": 100000}, ["TOP_CLASS"])["POST_MATRIC"]
    assert r["status"] == "NEEDS_REVIEW" and r["conflicts"] == ["TOP_CLASS"]


def test_holding_same_scheme_is_a_renewal():
    r = _status({"category": "ST", "course_level": "PG", "annual_family_income": 100000}, ["POST_MATRIC"])["POST_MATRIC"]
    assert r["status"] == "ELIGIBLE"


def test_overseas_age_limit():
    p = {"category": "ST", "course_level": "PG", "annual_family_income": 100000, "foreign_admission": True,
         "last_exam_percentage": 72, "dob": date(1985, 1, 1)}
    assert _status(p)["NOS"]["status"] == "NOT_ELIGIBLE"


# --------------------------------------------------------------- matching
def test_name_variants_match():
    for a, b in [("Sunita Oraon", "Sunitha Oraon"), ("Munda Ramesh", "Ramesh Munda"),
                 ("Ravi Kumar Gond", "Ravi Gond"), ("Shri Meena Soren", "Meena Soren")]:
        assert M.match_score({"name": a, "dob": "2009-03-04"}, {"name": b, "dob": "2009-03-04"}).decision == "MATCH", (a, b)


def test_different_people_do_not_match():
    assert M.match_score({"name": "Sunita Oraon", "dob": "2009-03-04"},
                         {"name": "Anita Hansda", "dob": "2009-03-04"}).decision == "NO_MATCH"


def test_same_name_different_dob_is_not_a_confident_match():
    assert M.match_score({"name": "Sunita Oraon", "dob": "2009-03-04"},
                         {"name": "Sunita Oraon", "dob": "2011-08-19"}).decision != "MATCH"


def test_apaar_id_is_decisive():
    r = M.match_score({"name": "A B", "apaar_id": "123456789012"}, {"name": "Totally Different", "apaar_id": "123456789012"})
    assert r.decision == "MATCH" and r.reason == "EXACT_ID"


def test_blocking_finds_the_right_record():
    pool = [{"id": 0, "name": "Sunitha Oraon", "dob": "2009-03-04", "state": "Jharkhand"},
            {"id": 1, "name": "Anita Hansda", "dob": "2008-01-01", "state": "Jharkhand"}]
    rec, res = M.Matcher(pool).best({"name": "Sunita Oraon", "dob": "2009-03-04", "state": "Jharkhand"})
    assert rec["id"] == 0 and res.decision == "MATCH"
    _, res = M.Matcher(pool).best({"name": "Birsa Kisku", "dob": "2001-01-01", "state": "Odisha"})
    assert res.decision == "NO_MATCH"


# ---------------------------------------------------------------- anomaly
def test_anomaly_flags_only_with_reasons():
    today = date(2026, 9, 20)
    normal = anomaly.build_features({"course_level": "UG", "dob": date(2005, 6, 1), "last_exam_percentage": 70,
                                     "annual_family_income": 110000}, {"checks": []}, 4, today)
    odd = anomaly.build_features({"course_level": "CLASS_10", "dob": date(1998, 6, 1), "last_exam_percentage": 99.5,
                                  "annual_family_income": 0},
                                 {"checks": [{"status": "MISMATCH", "components": {"name": 0.4, "dob": 0.0}},
                                             {"status": "MISMATCH", "components": {}}]}, 1, today)
    d = anomaly.get_detector()
    assert d.score(normal)["flagged"] is False
    verdict = d.score(odd)
    assert verdict["flagged"] is True and verdict["reasons"]
    json.dumps(verdict)  # must be JSON-serialisable


# ------------------------------------------------------------- lifecycle
def _states(status, ever=False, open_=False):
    return [s["state"] for s in build_timeline(status, [], ever, open_)]


def test_timeline_stages():
    assert _states("DRAFT") == ["current", "pending", "pending", "pending", "pending"]
    assert _states("UNDER_VERIFICATION") == ["done", "current", "pending", "pending", "pending"]
    assert _states("DEFICIENCY", True, True) == ["done", "done", "current", "pending", "pending"]
    assert _states("VERIFIED") == ["done", "done", "skipped", "current", "pending"]
    assert _states("DBT_PAID") == ["done", "done", "skipped", "done", "done"]
    assert _states("REJECTED") == ["done", "rejected", "skipped", "blocked", "blocked"]


def test_state_machine_blocks_shortcuts():
    assert can_transition("SUBMITTED", "UNDER_VERIFICATION")
    assert not can_transition("SUBMITTED", "SANCTIONED")
    assert not can_transition("DBT_PAID", "SUBMITTED")


# ------------------------------------------------------------ verification
class FakeGateway:
    def __init__(self, down=()):
        self.down = set(down)

    def call(self, source, op, **kw):
        if source in self.down:
            raise SourceUnavailable(source)
        if source == "UIDAI":
            return {"found": True, "name": "Sunitha Oraon", "dob": "2010-05-14", "gender": "F"}
        if source == "EDISTRICT":
            return {"found": True, "caste": {"category": "ST", "tribe": "Oraon", "valid": True}, "income": {"amount": 120000}}
        raise AssertionError(f"unexpected call {source}.{op}")


PROFILE = {"full_name": "Sunita Oraon", "dob": "2010-05-14", "gender": "F", "category": "ST", "tribe_name": "Oraon",
           "aadhaar_hash": "abc", "annual_family_income": 120000, "course_level": "CLASS_10"}


def test_verification_matches_and_scores():
    rep = run_verification(PROFILE, FakeGateway(), {"UIDAI", "EDISTRICT"})
    by = {c["source"]: c["status"] for c in rep["checks"]}
    assert by["UIDAI"] == "MATCH" and by["EDISTRICT"] == "MATCH"
    assert rep["confidence"] >= 0.95 and rep["mismatches"] == []


def test_no_consent_means_no_call():
    rep = run_verification(PROFILE, FakeGateway(), set())
    assert all(c["status"] in ("NO_CONSENT",) for c in rep["checks"]) and rep["confidence"] is None


def test_source_outage_is_reported_not_raised():
    rep = run_verification(PROFILE, FakeGateway(down={"UIDAI"}), {"UIDAI", "EDISTRICT"})
    assert rep["unavailable"] == ["UIDAI"]
    assert rep["status"] == "PARTIAL"  # other source still matched


def test_income_mismatch_goes_to_review():
    prof = {**PROFILE, "annual_family_income": 50000}
    rep = run_verification(prof, FakeGateway(), {"EDISTRICT"})
    assert rep["status"] == "NEEDS_REVIEW" and "EDISTRICT" in rep["mismatches"]


# --------------------------------------------------------------- assistant
def test_suggestion_chips_round_trip_in_both_languages():
    for lang in ("en", "hi"):
        got = [assistant.detect_intent(c) for c in assistant.T[lang]["chips"]]
        assert got == ["eligibility", "documents", "status", "deficiency"], (lang, got)


def test_short_keywords_do_not_fire_inside_words():
    assert assistant.detect_intent("hi") == "greeting"
    assert assistant.detect_intent("which one is this") != "greeting"


def test_reply_uses_students_own_data():
    ctx = {"name": "Sunita", "eligibility": [], "documents_have": [], "documents_by_scheme": {},
           "applications": [{"scheme_name": "Pre-Matric", "status": "DEFICIENCY",
                             "open_deficiencies": ["Upload your passbook"], "sanctioned": None, "paid": None}]}
    r = assistant.reply("Any corrections pending?", "en", ctx)
    assert "Upload your passbook" in r["reply"]
    assert assistant.reply("मेरा आवेदन कहाँ है?", "en", ctx)["language"] == "hi"
