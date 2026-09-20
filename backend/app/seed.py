"""Seed data.

seed_schemes  loads rule definitions from data/schemes.json (all environments).
seed_demo     creates DEMO accounts and SYNTHETIC records. Every name, ID, number and
              location below is fictional. Disable with SEED_DEMO=false, and never
              run against production.

Demo logins (change or remove before any real deployment):
  student   9000000001 / Student@123    (Sunita: verified profile, one correction pending)
            9000000002 / Student@123    (Ravi:   UIDAI date-of-birth mismatch, eligible for Top Class)
            9000000003 / Student@123    (Lakhan: PVTG, income missing, no consents yet)
            9000000004 / Student@123    (Meena:  PhD + UGC-NET, NFST sanctioned)
  verifier  9000000101 / Verifier@123
  ministry  9000000201 / Admin@123
"""
import json
import random
from datetime import date
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from .integrations.gateway import Gateway
from .models import (Application, Consent, Document, ExternalRegistry, ScholarshipRecord, Scheme,
                     SourceStudentRecord, StudentProfile, User)
from .security import encrypt_field, hash_identifier, hash_password
from .services import coverage_gap
from .services.student import apply_document_to_form, autofill
from .services.submission import push_to_portal
from .services.workflow import raise_deficiency, record_event, transition

ALL_CONSENTS = ["DIGILOCKER", "UIDAI", "APAAR", "ENROLMENT", "EDISTRICT", "UGC_NTA"]


def seed_schemes(db: Session) -> None:
    data = json.loads((Path(__file__).parent / "data" / "schemes.json").read_text(encoding="utf-8"))
    for s in data:
        row = db.get(Scheme, s["code"]) or Scheme(code=s["code"])
        for k in ("name", "short_name", "portal", "description", "documents", "rules", "conflicts_with"):
            setattr(row, k, s[k])
        db.add(row)
    db.commit()


# ------------------------------------------------------------------- students
STUDENTS = [
    dict(name="Sunita Oraon", phone="9000000001", dob=date(2010, 5, 14), g="F", tribe="Oraon", state="Jharkhand",
         district="Gumla", lat=23.04, lon=84.54, level="CLASS_10", course="Class X", inst="Govt. High School Gumla",
         inst_code="20011", notified=False, pct=78.0, apaar="100000000001", aadhaar="234100000001", income=120000,
         account="123456780001", ifsc="SBIN0001234", consents=ALL_CONSENTS,
         uidai=dict(name="Sunitha Oraon", dob="2010-05-14", gender="F"), cert_income=120000),
    dict(name="Ravi Kumar Gond", phone="9000000002", dob=date(2004, 11, 2), g="M", tribe="Gond", state="Madhya Pradesh",
         district="Mandla", lat=22.60, lon=80.37, level="UG", course="B.Sc. Physics", inst="Govt. PG College Mandla",
         inst_code="C-31207", notified=True, pct=82.0, apaar="100000000002", aadhaar="234100000002", income=450000,
         account="123456780002", ifsc="SBIN0005678", consents=ALL_CONSENTS,
         uidai=dict(name="Ravi Gond", dob="2003-11-02", gender="M"), cert_income=450000),  # DOB year differs: mismatch demo
    dict(name="Lakhan Baiga", phone="9000000003", dob=date(2009, 8, 21), g="M", tribe="Baiga", pvtg=True,
         state="Chhattisgarh", district="Kawardha", lat=22.01, lon=81.23, level="CLASS_11", course="Class XI",
         inst="Govt. Higher Secondary School Kawardha", inst_code="22045", notified=False, pct=None, apaar="100000000003",
         aadhaar="234100000003", income=None, account=None, ifsc=None, consents=[],
         uidai=dict(name="Lakhan Baiga", dob="2009-08-21", gender="M"), cert_income=90000),
    dict(name="Meena Soren", phone="9000000004", dob=date(1998, 2, 9), g="F", tribe="Santhal", state="Odisha",
         district="Mayurbhanj", lat=21.93, lon=86.73, level="PHD", course="PhD Anthropology", inst="Utkal University",
         inst_code="U-0121", notified=True, pct=71.0, apaar="100000000004", aadhaar="234100000004", income=180000,
         account="123456780004", ifsc="SBIN0009012", consents=ALL_CONSENTS, nta="NET-2024-8841",
         uidai=dict(name="Meena Soren", dob="1998-02-09", gender="F"), cert_income=180000),
]


def _registries(db: Session, s: dict, ahash: str) -> None:
    def put(source: str, key: str, payload: dict) -> None:
        db.add(ExternalRegistry(source=source, key=key, payload=payload))

    put("UIDAI", ahash, s["uidai"])
    put("EDISTRICT", ahash, {"caste": {"category": "ST", "tribe": s["tribe"], "valid": True},
                             "income": {"amount": s["cert_income"]}})
    put("APAAR", s["apaar"], {"name": s["name"], "dob": s["dob"].isoformat(), "institution_name": s["inst"]})
    source = "UDISE" if s["level"].startswith("CLASS") else "AISHE"
    if not db.scalar(select(ExternalRegistry).where(ExternalRegistry.source == source, ExternalRegistry.key == s["inst_code"])):
        put(source, s["inst_code"], {"name": s["inst"], "top_class_notified": s["notified"]})
    if s.get("nta"):
        put("UGC_NTA", s["nta"], {"qualified": True, "name": s["name"]})
    docs = [
        {"uri": f"in.gov.edistrict-CASTE-{s['apaar'][-4:]}", "doc_type": "CASTE_CERT", "issuer": f"Revenue Dept, {s['state']}",
         "doc_number": f"ST/{s['apaar'][-4:]}/2024", "issued_on": "2024-03-01", "data": {"tribe": s["tribe"], "category": "ST"}},
        {"uri": f"in.gov.edistrict-INCOME-{s['apaar'][-4:]}", "doc_type": "INCOME_CERT", "issuer": f"e-District, {s['state']}",
         "doc_number": f"INC/{s['apaar'][-4:]}/2026", "issued_on": "2026-04-10", "data": {"amount": s["cert_income"]}},
    ]
    if s["pct"] is not None:
        docs.append({"uri": f"in.gov.board-MARKS-{s['apaar'][-4:]}", "doc_type": "MARKSHEET", "issuer": "Board / University",
                     "doc_number": f"MS/{s['apaar'][-4:]}", "issued_on": "2026-05-20", "data": {"percentage": s["pct"]}})
    if s.get("nta"):
        docs.append({"uri": f"in.gov.nta-NET-{s['apaar'][-4:]}", "doc_type": "NET_JRF_CERT", "issuer": "NTA (UGC-NET)",
                     "doc_number": s["nta"], "issued_on": "2024-08-30", "data": {"roll": s["nta"]}})
    put("DIGILOCKER", s["phone"], {"documents": docs})


def _seed_students(db: Session) -> dict[str, User]:
    users: dict[str, User] = {}
    for s in STUDENTS:
        u = User(phone=s["phone"], full_name=s["name"], password_hash=hash_password("Student@123"), role="STUDENT",
                 language="hi" if s["phone"].endswith("1") else "en")
        db.add(u)
        db.flush()
        ahash = hash_identifier(s["aadhaar"])
        p = StudentProfile(
            user_id=u.id, dob=s["dob"], gender=s["g"], tribe_name=s["tribe"], is_pvtg=s.get("pvtg", False),
            state=s["state"], district=s["district"], lat=s["lat"], lon=s["lon"], course_level=s["level"],
            course_name=s["course"], institution_name=s["inst"], institution_code=s["inst_code"],
            institution_top_class_notified=s["notified"], last_exam_percentage=s["pct"], apaar_id=s["apaar"],
            aadhaar_hash=ahash, aadhaar_last4=s["aadhaar"][-4:], annual_family_income=s["income"],
            ugc_nta_qualified=bool(s.get("nta")), ugc_nta_roll=s.get("nta"), active_scholarships=[],
        )
        if s["account"]:
            p.bank_account_enc, p.bank_account_hash = encrypt_field(s["account"]), hash_identifier(s["account"])
            p.bank_account_last4, p.ifsc = s["account"][-4:], s["ifsc"]
        db.add(p)
        for purpose in s["consents"]:
            db.add(Consent(user_id=u.id, purpose=purpose, granted=True))
        _registries(db, s, ahash)
        users[s["phone"]] = u
    db.flush()
    return users


def _doc(db: Session, user: User, s_phone: str, doc_type: str) -> Document:
    reg = db.scalar(select(ExternalRegistry).where(ExternalRegistry.source == "DIGILOCKER", ExternalRegistry.key == s_phone))
    d = next(x for x in reg.payload["documents"] if x["doc_type"] == doc_type)
    doc = Document(user_id=user.id, doc_type=doc_type, source="DIGILOCKER", uri=d["uri"], issuer=d["issuer"],
                   doc_number=d["doc_number"], issued_on=date.fromisoformat(d["issued_on"]), extracted=d["data"], verified=True)
    db.add(doc)
    db.flush()
    return doc


def _seed_applications(db: Session, users: dict[str, User]) -> None:
    gw = Gateway(db)

    # Sunita: Pre-Matric waiting on a correction
    u = users["9000000001"]
    p = db.scalar(select(StudentProfile).where(StudentProfile.user_id == u.id))
    scheme = db.get(Scheme, "PRE_MATRIC")
    docs = [_doc(db, u, "9000000001", t) for t in ("CASTE_CERT", "INCOME_CERT", "MARKSHEET")]
    form = autofill(p, "PRE_MATRIC")
    for d in docs:
        form = apply_document_to_form(d, form)
    app = Application(user_id=u.id, scheme_code="PRE_MATRIC", status="DRAFT", form_data=form, document_ids=[d.id for d in docs])
    db.add(app)
    db.flush()
    record_event(db, app, "APPLICATION", "DRAFT", note="Draft created", actor_role="STUDENT")
    transition(db, app, "SUBMITTED", actor_role="STUDENT", scheme_name=scheme.short_name)
    push_to_portal(db, app, scheme, p, gw)
    transition(db, app, "UNDER_VERIFICATION", note="Sent for verification", scheme_name=scheme.short_name)
    raise_deficiency(db, app, "Upload a clear photo or scan of your bank passbook first page", doc_type="BANK_PASSBOOK",
                     raised_by=None, scheme_name=scheme.short_name)

    # Meena: NFST sanctioned, payment pending
    u = users["9000000004"]
    p = db.scalar(select(StudentProfile).where(StudentProfile.user_id == u.id))
    scheme = db.get(Scheme, "NFST")
    docs = [_doc(db, u, "9000000004", t) for t in ("CASTE_CERT", "NET_JRF_CERT")]
    app = Application(user_id=u.id, scheme_code="NFST", status="DRAFT", form_data=autofill(p, "NFST"), document_ids=[d.id for d in docs])
    db.add(app)
    db.flush()
    record_event(db, app, "APPLICATION", "DRAFT", note="Draft created", actor_role="STUDENT")
    transition(db, app, "SUBMITTED", actor_role="STUDENT", scheme_name=scheme.short_name)
    push_to_portal(db, app, scheme, p, gw)
    transition(db, app, "UNDER_VERIFICATION", scheme_name=scheme.short_name)
    transition(db, app, "VERIFIED", actor_role="VERIFIER", scheme_name=scheme.short_name)
    transition(db, app, "SANCTIONED", actor_role="ADMIN", amount=372000, scheme_name=scheme.short_name)


# ------------------------------------------------------- population (ministry)
_FIRST_F = ["Sunita", "Meena", "Lakshmi", "Anita", "Rina", "Kavita", "Sushila", "Pooja", "Geeta", "Sarita", "Manju", "Basanti"]
_FIRST_M = ["Ravi", "Mangal", "Sanjay", "Dinesh", "Ramesh", "Birsa", "Suresh", "Anil", "Kishan", "Rajesh", "Sukhram", "Budhram"]
_LAST = {
    "Jharkhand": ["Munda", "Oraon", "Hansda", "Soren", "Kisku"], "Odisha": ["Majhi", "Kandha", "Bhuyan", "Santal", "Naik"],
    "Chhattisgarh": ["Gond", "Baiga", "Netam", "Markam", "Korram"], "Madhya Pradesh": ["Gond", "Bhil", "Uikey", "Maravi", "Dhurve"],
    "Maharashtra": ["Pardhan", "Warli", "Gavit", "Madavi", "Kokni"], "Gujarat": ["Bhil", "Vasava", "Rathwa", "Gamit", "Chaudhari"],
    "Tripura": ["Debbarma", "Reang", "Jamatia", "Noatia"],
}
_DISTRICTS = {
    "Jharkhand": [("Ranchi", 23.36, 85.33), ("Gumla", 23.04, 84.54), ("West Singhbhum", 22.55, 85.80), ("Dumka", 24.27, 87.25)],
    "Odisha": [("Mayurbhanj", 21.93, 86.73), ("Koraput", 18.81, 82.71), ("Kandhamal", 20.47, 84.23)],
    "Chhattisgarh": [("Bastar", 19.10, 81.95), ("Surguja", 23.12, 83.20), ("Kawardha", 22.01, 81.23)],
    "Madhya Pradesh": [("Mandla", 22.60, 80.37), ("Jhabua", 22.77, 74.59), ("Dindori", 22.95, 81.08)],
    "Maharashtra": [("Gadchiroli", 20.18, 80.00), ("Nandurbar", 21.37, 74.24)],
    "Gujarat": [("Dahod", 22.84, 74.26), ("Narmada", 21.87, 73.50)],
    "Tripura": [("Dhalai", 23.85, 91.87)],
}
_LEVELS = [("CLASS_9", 14.5), ("CLASS_10", 15.5), ("CLASS_11", 16.5), ("CLASS_12", 17.5), ("UG", 20.0), ("PG", 22.5)]


def _variant(rng: random.Random, name: str) -> str:
    opts = [name.replace("Sunita", "Sunitha"), " ".join(reversed(name.split())), name.replace("Kumar ", ""),
            "Shri " + name, name.replace("Ravi", "Rabi"), name.replace("Oraon", "Oraan")]
    return rng.choice(opts)


def _seed_population(db: Session, n: int = 320) -> None:
    rng = random.Random(7)
    used = {"100000000001", "100000000002", "100000000003", "100000000004"}
    seeded_pairs = [("Ravi Kumar Gond", "100000000002", "Madhya Pradesh", "Mandla", "UG", date(2004, 11, 2), "M"),
                    ("Lakhan Baiga", "100000000003", "Chhattisgarh", "Kawardha", "CLASS_11", date(2009, 8, 21), "M")]
    rows: list[SourceStudentRecord] = []
    for name, apaar, state, dist, level, dob, g in seeded_pairs:  # registered demo students who are NOT covered
        lat, lon = next((la, lo) for d, la, lo in _DISTRICTS[state] if d == dist)
        rows.append(SourceStudentRecord(source="APAAR", apaar_id=apaar, name=name, dob=dob, gender=g, category="ST", state=state,
                                        district=dist, institution_name="Govt. School/College " + dist, class_level=level,
                                        mobile="9000000002" if "Ravi" in name else "9000000003", lat=lat, lon=lon))
    for _ in range(n):
        state = rng.choice(list(_DISTRICTS))
        dist, la, lo = rng.choice(_DISTRICTS[state])
        g = rng.choice("MF")
        name = f"{rng.choice(_FIRST_F if g == 'F' else _FIRST_M)} {rng.choice(_LAST[state])}"
        level, age = rng.choice(_LEVELS)
        dob = date(2026 - int(age) - 1, rng.randint(1, 12), rng.randint(1, 28))
        while True:
            apaar = str(rng.randrange(10**11, 10**12))
            if apaar not in used:
                used.add(apaar)
                break
        rows.append(SourceStudentRecord(
            source="UDISE_PLUS" if level.startswith("CLASS") else "AISHE", apaar_id=apaar, name=name, dob=dob, gender=g,
            category="ST" if rng.random() > 0.08 else "GEN", state=state, district=dist,
            institution_name=f"Govt. {'School' if level.startswith('CLASS') else 'College'} {dist}", class_level=level,
            mobile=f"9{rng.randrange(10**8, 10**9)}", lat=la + rng.uniform(-.15, .15), lon=lo + rng.uniform(-.15, .15)))
    db.add_all(rows)
    db.flush()

    for r in rows:
        if r.apaar_id in ("100000000002", "100000000003") or r.category != "ST":
            continue
        roll = rng.random()
        if roll > 0.70:
            continue  # ~30% have no scholarship record: potential coverage gaps
        scheme = ("PRE_MATRIC" if r.class_level in ("CLASS_9", "CLASS_10") else "TOP_CLASS" if r.class_level == "UG" and rng.random() < .2
                  else "POST_MATRIC")
        name, apaar, dob = r.name, r.apaar_id, r.dob
        if roll > 0.50:  # transliteration / order variants, sometimes without the APAAR ID
            name = _variant(rng, r.name)
            apaar = None if rng.random() < .8 else r.apaar_id
        if roll > 0.66 and dob:  # day/month typed the wrong way round
            dob = date(dob.year, dob.day, dob.month) if dob.day <= 12 else dob
        db.add(ScholarshipRecord(portal="SFMP" if scheme == "TOP_CLASS" else "NSP/OTR", scheme_code=scheme, apaar_id=apaar,
                                 name=name, dob=dob, gender=r.gender, state=r.state, district=r.district,
                                 institution_name=r.institution_name, status=rng.choice(["SUBMITTED", "VERIFIED", "SANCTIONED", "DBT_PAID"]),
                                 external_ref=f"{'SFMP' if scheme == 'TOP_CLASS' else 'NSP'}-2026-{rng.randrange(10**7, 10**8)}"))
    db.flush()


def seed_demo(db: Session) -> None:
    if db.scalar(select(User).where(User.phone == "9000000001")):
        return
    users = _seed_students(db)
    for phone, email, name, role, pw in [("9000000101", "verifier@example.gov", "Demo Verifier", "VERIFIER", "Verifier@123"),
                                         ("9000000201", "admin@example.gov", "Demo Ministry Admin", "ADMIN", "Admin@123")]:
        db.add(User(phone=phone, email=email, full_name=name, role=role, password_hash=hash_password(pw)))
    _seed_applications(db, users)
    _seed_population(db)
    db.commit()
    coverage_gap.run_detection(db)  # so the ministry dashboard has content on first open
    db.commit()
