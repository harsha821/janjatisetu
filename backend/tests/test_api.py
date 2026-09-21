"""End-to-end API tests. Run with: pytest  (needs the packages in requirements.txt).

Uses the demo seed:
  Sunita (9000000001) Pre-Matric with one open correction
  Ravi   (9000000002) UIDAI date-of-birth mismatch, eligible for Top Class
  Lakhan (9000000003) income missing, no consents
"""
import pytest
from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

API = "/api/v1"
PDF = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF"


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def login(client, phone, password):
    r = client.post(f"{API}/auth/login", data={"username": phone, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture(scope="module")
def sunita(client):
    return login(client, "9000000001", "Student@123")


@pytest.fixture(scope="module")
def ravi(client):
    return login(client, "9000000002", "Student@123")


@pytest.fixture(scope="module")
def verifier(client):
    return login(client, "9000000101", "Verifier@123")


@pytest.fixture(scope="module")
def admin(client):
    return login(client, "9000000201", "Admin@123")


def test_bad_password_rejected(client):
    r = client.post(f"{API}/auth/login", data={"username": "9000000001", "password": "wrong"})
    assert r.status_code == 401


def test_dashboard_shows_pending_correction_first(client, sunita):
    d = client.get(f"{API}/dashboard", headers=sunita).json()
    assert d["applications"][0]["status"] == "DEFICIENCY"
    assert d["next_step"]["kind"] == "DEFICIENCY"
    stages = [s["state"] for s in d["applications"][0]["timeline"]]
    assert stages == ["done", "done", "current", "pending", "pending"]


def test_role_guards(client, sunita, verifier):
    assert client.get(f"{API}/admin/overview", headers=sunita).status_code == 403
    assert client.get(f"{API}/dashboard", headers=verifier).status_code == 403
    assert client.get(f"{API}/admin/coverage-gap", headers=verifier).status_code == 403
    assert client.get(f"{API}/dashboard").status_code == 401


def test_eligibility_for_ravi(client, ravi):
    r = {e["scheme_code"]: e["status"] for e in client.get(f"{API}/eligibility", headers=ravi).json()}
    assert r["TOP_CLASS"] == "ELIGIBLE"
    assert r["POST_MATRIC"] == "NOT_ELIGIBLE"  # income above the limit


def test_digilocker_needs_consent(client):
    lakhan = login(client, "9000000003", "Student@123")
    assert client.get(f"{API}/wallet/digilocker", headers=lakhan).status_code == 403


def test_submit_with_missing_documents_goes_to_manual_review(client, ravi):
    app_ = client.post(f"{API}/applications", json={"scheme_code": "TOP_CLASS"}, headers=ravi).json()
    r = client.post(f"{API}/applications/{app_['id']}/submit", headers=ravi)
    assert r.status_code == 200
    assert r.json()["status"] == "UNDER_VERIFICATION"



def test_full_journey_with_mismatch_routed_to_review(client, ravi, verifier, admin):
    # wallet: DigiLocker items + two uploads
    for d in client.get(f"{API}/wallet/digilocker", headers=ravi).json():
        assert client.post(f"{API}/wallet/import", json={"uri": d["uri"]}, headers=ravi).status_code == 201
    for t in ("ADMISSION_LETTER", "BANK_PASSBOOK"):
        r = client.post(f"{API}/wallet/upload", data={"doc_type": t}, files={"file": (f"{t}.pdf", PDF, "application/pdf")}, headers=ravi)
        assert r.status_code == 201, r.text
    docs = client.get(f"{API}/wallet/documents", headers=ravi).json()
    # Create a fresh application for Ravi to avoid conflicting with previous tests
    app_id = client.post(f"{API}/applications", json={"scheme_code": "TOP_CLASS", "academic_year": "2025-26"}, headers=ravi).json()["id"]
    client.put(f"{API}/applications/{app_id}", json={"document_ids": [d["id"] for d in docs]}, headers=ravi)

    sub = client.post(f"{API}/applications/{app_id}/submit", headers=ravi)
    assert sub.status_code == 200, sub.text
    body = sub.json()
    assert body["status"] == "UNDER_VERIFICATION" and body["external_ref"]

    # the UIDAI date-of-birth mismatch became a review case, not a rejection
    cases = client.get(f"{API}/admin/exceptions", headers=verifier).json()
    mine = [c for c in cases if c["application_id"] == app_id and c["kind"] == "DATA_MISMATCH"]
    assert mine and mine[0]["severity"] in ("HIGH", "MEDIUM")

    # reviewer cannot verify while cases are open
    r = client.post(f"{API}/admin/applications/{app_id}/action", json={"action": "VERIFY"}, headers=verifier)
    assert r.status_code == 409
    for c in [c for c in cases if c["application_id"] == app_id]:
        client.post(f"{API}/admin/exceptions/{c['id']}/resolve", json={"resolution": "CONFIRMED_OK", "note": "Checked original"}, headers=verifier)
    assert client.post(f"{API}/admin/applications/{app_id}/action", json={"action": "VERIFY"}, headers=verifier).status_code == 200

    # sanction + pay need their inputs; rejection needs a reason
    assert client.post(f"{API}/admin/applications/{app_id}/action", json={"action": "SANCTION"}, headers=verifier).status_code == 422
    assert client.post(f"{API}/admin/applications/{app_id}/action", json={"action": "SANCTION", "amount": 50000}, headers=verifier).status_code == 200
    assert client.post(f"{API}/admin/applications/{app_id}/action", json={"action": "PAY", "amount": 50000, "utr": "UTR123456"}, headers=verifier).status_code == 200
    final = client.get(f"{API}/applications/{app_id}", headers=ravi).json()
    assert final["status"] == "DBT_PAID" and final["paid_amount"] == 50000
    assert [s["state"] for s in final["timeline"]] == ["done", "done", "skipped", "done", "done"]

    notes = client.get(f"{API}/notifications", headers=ravi).json()
    assert any(n["kind"] == "PAYMENT" for n in notes)


def test_correction_flow(client, sunita):
    d = client.get(f"{API}/dashboard", headers=sunita).json()["applications"][0]
    r = client.post(f"{API}/applications/{d['id']}/deficiencies/{d['open_deficiencies'][0]['id']}/resolve",
                    json={"note": "Uploaded a clearer passbook"}, headers=sunita)
    assert r.status_code == 200 and r.json()["status"] == "UNDER_VERIFICATION"


def test_offline_sync_is_idempotent(client, sunita):
    op = {"op_id": "op-test-0001", "type": "UPDATE_PROFILE", "payload": {"course_name": "Class X (updated offline)"}}
    first = client.post(f"{API}/sync/push", json={"operations": [op]}, headers=sunita).json()["results"][0]
    again = client.post(f"{API}/sync/push", json={"operations": [op]}, headers=sunita).json()["results"][0]
    assert first["ok"] and again["replayed"] is True
    pulled = client.get(f"{API}/sync/pull", headers=sunita).json()
    assert pulled["profile"]["course_name"] == "Class X (updated offline)" and pulled["schemes"]


def test_edit_after_review_is_a_conflict_not_an_overwrite(client, sunita):
    app_id = client.get(f"{API}/dashboard", headers=sunita).json()["applications"][0]["id"]
    op = {"op_id": "op-test-0002", "type": "UPDATE_APPLICATION", "application_id": app_id, "payload": {"form_data": {"district": "X"}}}
    res = client.post(f"{API}/sync/push", json={"operations": [op]}, headers=sunita).json()["results"][0]
    assert res["ok"] is False and res["error"] == "CONFLICT" and res["application"]["id"] == app_id


def test_verification_reports_outage_instead_of_failing(client, sunita):
    settings.simulate_outages = "UIDAI"
    try:
        r = client.post(f"{API}/profile/verify", headers=sunita)
        assert r.status_code == 200 and "UIDAI" in r.json()["unavailable"]
    finally:
        settings.simulate_outages = ""


def test_coverage_gap_flow(client, admin):
    funnel = client.post(f"{API}/admin/coverage-gap/run", headers=admin).json()
    assert funnel["enrolled_st"] > 0 and funnel["potential_gap"] > 0
    assert "not proof" in funnel["note"]
    assert funnel["matched"] + funnel["uncertain"] + funnel["potential_gap"] == funnel["enrolled_st"]

    validated = client.get(f"{API}/admin/coverage-gap", params={"state": "VALIDATED"}, headers=admin).json()
    assert validated["total"] > 0
    ids = [g["id"] for g in validated["items"][:5]]
    out = client.post(f"{API}/admin/coverage-gap/outreach", json={"gap_ids": ids, "channel": "JAGO"}, headers=admin).json()
    assert out["sent"] == len(ids)
    # already-contacted cases are not contacted twice
    again = client.post(f"{API}/admin/coverage-gap/outreach", json={"gap_ids": ids, "channel": "JAGO"}, headers=admin).json()
    assert again["sent"] == 0 and again["skipped"] == len(ids)

    audit = client.get(f"{API}/admin/audit", headers=admin).json()
    assert any(a["action"] == "SEND_OUTREACH" for a in audit)


def test_rerunning_gap_detection_does_not_duplicate_review_cases(client, admin):
    client.post(f"{API}/admin/coverage-gap/run", headers=admin)
    first = client.get(f"{API}/admin/exceptions", params={"kind": "RECORD_MATCH_UNCERTAIN", "limit": 300}, headers=admin).json()
    client.post(f"{API}/admin/coverage-gap/run", headers=admin)
    second = client.get(f"{API}/admin/exceptions", params={"kind": "RECORD_MATCH_UNCERTAIN", "limit": 300}, headers=admin).json()
    assert len(second) == len(first)


def test_coverage_gap_can_be_fixed_by_a_reviewer(client, admin, verifier):
    client.post(f"{API}/admin/coverage-gap/run", headers=admin)
    items = client.get(f"{API}/admin/coverage-gap", params={"state": "VALIDATED"}, headers=admin).json()["items"]
    assert len(items) >= 4
    a, b, c, d = (g["id"] for g in items[:4])
    url = lambda gid: f"{API}/admin/coverage-gap/{gid}/resolve"  # noqa: E731

    # only ADMIN may fix gaps; unknown ids are a 404
    assert client.post(url(a), json={"action": "DISMISS", "note": "x"}, headers=verifier).status_code == 403
    assert client.post(url(999999), json={"action": "REOPEN"}, headers=admin).status_code == 404

    # dismissing needs a written reason
    assert client.post(url(a), json={"action": "DISMISS"}, headers=admin).status_code == 400
    r = client.post(url(a), json={"action": "DISMISS", "note": "Family moved out of state"}, headers=admin)
    assert r.status_code == 200 and r.json()["state"] == "DISMISSED"
    assert "moved out of state" in r.json()["reason"]

    # a dismissed gap is never contacted
    out = client.post(f"{API}/admin/coverage-gap/outreach", json={"gap_ids": [a], "channel": "JAGO"}, headers=admin).json()
    assert out["sent"] == 0 and out["skipped"] == 1

    # a gap closed by hand can be closed only once
    r = client.post(url(b), json={"action": "MARK_APPLIED", "note": "Paper application at block office"}, headers=admin)
    assert r.status_code == 200 and r.json()["state"] == "APPLIED"
    assert client.post(url(b), json={"action": "MARK_APPLIED"}, headers=admin).status_code == 409
    assert client.post(url(b), json={"action": "DISMISS", "note": "x"}, headers=admin).status_code == 409

    # reopening sends it back through validation
    r = client.post(url(a), json={"action": "REOPEN"}, headers=admin)
    assert r.status_code == 200 and r.json()["state"] == "VALIDATED"

    # outreach reports what actually happened: SMS is disabled in tests, so nothing is delivered
    out = client.post(f"{API}/admin/coverage-gap/outreach", json={"gap_ids": [c, d], "channel": "SMS"}, headers=admin).json()
    assert out["sent"] == 2 and out["delivered"] == 0 and out["undelivered"] == 2
    assert out["delivered"] + out["queued"] + out["undelivered"] == out["sent"]
    contacted = client.get(f"{API}/admin/coverage-gap", params={"state": "OUTREACH_SENT"}, headers=admin).json()["items"]
    row = next(g for g in contacted if g["id"] == c)
    assert row["outreach_status"] == "UNDELIVERED" and "could not be delivered" in row["reason"]

    # ...and an undelivered case can be reopened to try another channel
    r = client.post(url(c), json={"action": "REOPEN"}, headers=admin)
    assert r.status_code == 200 and r.json()["state"] == "VALIDATED"
    queued = client.post(f"{API}/admin/coverage-gap/outreach", json={"gap_ids": [c], "channel": "INSTITUTION"}, headers=admin).json()
    assert queued["queued"] == 1 and queued["undelivered"] == 0

    audit = client.get(f"{API}/admin/audit", headers=admin).json()
    assert any(a["action"] == "RESOLVE_COVERAGE_GAP" for a in audit)


def test_jago_answers_in_hindi_and_english(client, sunita):
    en = client.post(f"{API}/assistant/chat", json={"message": "Where is my application?"}, headers=sunita).json()
    hi = client.post(f"{API}/assistant/chat", json={"message": "मेरा आवेदन कहाँ है?"}, headers=sunita).json()
    assert en["intent"] == "status" and hi["language"] == "hi"


def test_digilocker_oauth_connect_returns_url(client, sunita):
    """GET /wallet/digilocker/connect returns a well-formed response.

    When sandbox credentials are not configured (the default in tests),
    ``sandbox_configured`` must be False and no ``auth_url`` is present.
    When credentials ARE configured the response must include an ``auth_url``
    that starts with the DigiLocker base URL.
    """
    r = client.get(f"{API}/wallet/digilocker/connect", headers=sunita)
    assert r.status_code == 200
    body = r.json()
    # Either sandbox is configured (has auth_url) or not (has message)
    if body.get("sandbox_configured"):
        assert "auth_url" in body
        base = settings.digilocker_base_url
        assert body["auth_url"].startswith(base), f"auth_url should start with {base}"
        assert "already_connected" in body
    else:
        # No credentials in .env → graceful degradation
        assert body["sandbox_configured"] is False
        assert "message" in body


def test_digilocker_status_endpoint(client, sunita):
    """GET /wallet/digilocker/status returns connection state."""
    r = client.get(f"{API}/wallet/digilocker/status", headers=sunita)
    assert r.status_code == 200
    body = r.json()
    assert "sandbox_configured" in body
    assert "connected" in body
    # In tests the demo student has no stored token
    assert body["connected"] is False


def test_verification_checklist_is_scheme_aware(client, sunita, ravi):
    """GET /applications/{id}/verification-checklist returns scheme-aware steps.

    Covers three scenarios:
    1. Sunita — PRE_MATRIC, CLASS_10: UDISE present, no AISHE, no 12th/uni marksheet.
    2. Ravi   — POST_MATRIC, UG, no semester set (treated as sem 1): AISHE present,
                no UDISE, no UNIVERSITY_MARKSHEET.
    3. Standalone endpoint — POST_MATRIC + UG + semester=2: UNIVERSITY_MARKSHEET required.
    """
    # ── 1. Sunita: PRE_MATRIC CLASS_10 ──────────────────────────────────────
    sunita_app_id = client.get(f"{API}/dashboard", headers=sunita).json()["applications"][0]["id"]
    r = client.get(f"{API}/applications/{sunita_app_id}/verification-checklist", headers=sunita)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["scheme_code"] == "PRE_MATRIC"

    steps_by_id = {s["id"]: s for s in body["steps"]}

    # UDISE must be applicable (school student)
    assert steps_by_id["UDISE"]["applicable"] is True
    assert steps_by_id["UDISE"]["status"] != "NOT_APPLICABLE"

    # AISHE must NOT be applicable
    assert steps_by_id["AISHE"]["applicable"] is False
    assert steps_by_id["AISHE"]["status"] == "NOT_APPLICABLE"

    # 12th marksheet and university marksheet must not apply
    assert steps_by_id["TWELFTH_MARKSHEET"]["applicable"] is False
    assert steps_by_id["UNIVERSITY_MARKSHEET"]["applicable"] is False

    # 10th marksheet must apply (she is in Class 10)
    assert steps_by_id["TENTH_MARKSHEET"]["applicable"] is True

    # Structure sanity
    assert body["total"] > 0
    assert "verified" in body

    # ── 2. Ravi: POST_MATRIC UG (no semester → treated as 1) ─────────────────
    ravi_app_id = client.get(f"{API}/dashboard", headers=ravi).json()["applications"][0]["id"]
    r2 = client.get(f"{API}/applications/{ravi_app_id}/verification-checklist", headers=ravi)
    assert r2.status_code == 200, r2.text
    body2 = r2.json()

    steps2 = {s["id"]: s for s in body2["steps"]}
    assert steps2["AISHE"]["applicable"] is True, "College student must have AISHE"
    assert steps2["UDISE"]["applicable"] is False, "College student must not have UDISE"
    # No semester set → treated as 1 → university marksheet not yet required
    assert steps2["UNIVERSITY_MARKSHEET"]["applicable"] is False, "Sem 1 should not require uni marksheet"

    # ── 3. Standalone endpoint: POST_MATRIC + UG + semester=2 ────────────────
    r3 = client.get(
        f"{API}/verification-requirements",
        params={"scheme_code": "POST_MATRIC", "course_level": "UG", "semester": 2},
    )
    assert r3.status_code == 200, r3.text
    body3 = r3.json()
    steps3 = {s["id"]: s for s in body3["steps"]}
    assert steps3["UNIVERSITY_MARKSHEET"]["applicable"] is True, "Sem 2 must require university marksheet"
    assert steps3["UNIVERSITY_MARKSHEET"]["required"] is True
    # No auth needed for the standalone endpoint — confirm it returns the right structure
    assert "total" in body3 and "steps" in body3
