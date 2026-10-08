<div align="center">

# 🌱 JanjatiSetu

### Unified Scholarship Orchestration Platform for Tribal Students

**One Platform. Multiple Schemes. Brighter Futures.**

[Overview](#-overview) · [Architecture](#-system-architecture) · [Features](#-key-features) · [AI/ML](#-aiml-design) · [Quick Start](#-quick-start) · [API](#-api-surface-planned) · [Roadmap](#-roadmap)

</div>

---

## 📖 Overview

**JanjatiSetu** is a proposed, mobile-first **scholarship orchestration layer** that gives tribal students a single window to discover, apply for, and track scholarships and fellowships spread across multiple government portals.

Rather than replacing existing systems, it sits **on top of them** and integrates through **authorized APIs and adapters**, providing:

- a **unified student profile** (enter once, reuse everywhere),
- a **deterministic, explainable eligibility engine**,
- a **consent-based document wallet**,
- **cross-system status tracking** from application to DBT,
- **AI-assisted anomaly flags** for human reviewers, and
- a **multilingual assistant (JAGO)** with **offline-first** operation.

> ⚠️ **Prototype notice:** JanjatiSetu is a proposed/prototype solution. Real government integrations require official APIs, permissions and data-sharing agreements. See [Disclaimer](#️-disclaimer).

---

## 🎯 Problem Statement

| # | Pain point | Impact |
|---|-----------|--------|
| 1 | Multiple portals, fragmented workflows | Students must learn several systems |
| 2 | Repeated data entry and document upload | Errors, delays, dropouts |
| 3 | Opaque eligibility criteria | Eligible students never apply |
| 4 | Poor visibility of deficiency / sanction / DBT | No clarity on next steps |
| 5 | Low connectivity in remote regions | Applications interrupted |
| 6 | Language and digital-literacy barriers | Exclusion from benefits |
| 7 | Data mismatches across systems | Rejections and duplicate records |

---

## 💡 Solution

A single application lifecycle across all supported schemes:

```mermaid
flowchart LR
    A[Applied] --> B[Verification]
    B -->|Deficiency| C[Correction]
    C --> B
    B --> D[Sanction]
    D --> E[DBT]
```

---

## ✨ Key Features

<table>
<tr>
<td width="50%" valign="top">

### 🖥️ Unified Dashboard
Single view of application, verification, deficiency, correction, sanction and DBT status across supported systems.

### 🪪 Unified Student Profile
Canonical 360° profile (identity, ST/PVTG info, academics, institution, income, bank). A **schema-mapping layer** transforms it into each scheme's required format.

### 🧮 Multi-Scheme Eligibility Engine
Configurable rule engine detecting eligible schemes, duplicate benefits, concurrent applications and conflicts. Decisions are **deterministic, explainable, auditable**.

### 📄 Document Wallet
Consent-based storage and reuse of documents with **DigiLocker** verification.

### 🔍 Cross-System Verification
Entity resolution and record matching to surface duplicates, inconsistencies and mismatches.

</td>
<td width="50%" valign="top">

### 🤖 AI Anomaly Detection
Isolation Forest + XGBoost confidence scoring. Flags assist **authorized human reviewers**; they never auto-decide sanctions.

### 🗣️ JAGO Assistant
Multilingual **LLM + RAG + IndicTrans2** assistant aware of the student's status, pending actions, deficiencies and required documents.

### 📱 Offline-First
SQLite local store + sync queue; lightweight **PWA** for low-end devices and low bandwidth.

### 📊 Admin Coverage-Gap Intelligence
Identify potential students without scholarship records, validate against rules, and plan targeted outreach.

### 🔔 Multichannel Outreach
FCM push, Twilio SMS and WhatsApp alerts for milestones, deficiencies, sanctions and DBT.

</td>
</tr>
</table>

---

## 🏗️ System Architecture

```mermaid
flowchart TB
    subgraph Clients
        A1[Android]
        A2[iOS]
        A3[Web / PWA]
    end

    subgraph App["Flutter Application"]
        S[Student Portal]
        M[Ministry / Admin Portal]
    end

    subgraph Backend["FastAPI Backend (Python REST)"]
        GW[API Layer + AuthN/Z]
        subgraph ML["AI / ML Service Layer"]
            E1[Eligibility Engine]
            E2[Record Matching]
            E3[Coverage Gap]
            E4[Anomaly Detection]
            E5[Verification Scoring]
            E6[JAGO Chatbot]
        end
        subgraph INT["Integration & Document Wallet"]
            I1[API Gateway / Adapters]
            I2[Identity Matching]
            I3[Document Wallet]
            I4[Status Sync Workers]
        end
    end

    subgraph Data
        PG[(PostgreSQL)]
        RD[(Redis)]
    end

    subgraph Gov["Government Data Sources"]
        G1[NSP / OTR]
        G2[SFMP]
        G3[NOS]
        G4[DigiLocker]
        G5[UIDAI / e-KYC]
        G6[APAAR]
        G7[AISHE]
        G8[UDISE+]
    end

    Clients --> App --> GW
    GW --> ML
    GW --> INT
    ML --> PG
    INT --> PG
    GW --> RD
    I1 --> Gov
```

### Design principles

| Principle | How it is applied |
|-----------|-------------------|
| **Non-invasive integration** | Adapter pattern; no changes required to existing portals |
| **Deterministic core, probabilistic assist** | Eligibility = rules. ML = flags for human review only |
| **Consent first** | Documents and data shared only with explicit student consent |
| **Offline tolerant** | Local-first writes, queued sync, idempotent replays |
| **Phased rollout** | Modular services deployable independently |

---

## 🔄 Application Workflow

```mermaid
sequenceDiagram
    autonumber
    actor S as Student
    participant App as Flutter App
    participant API as FastAPI
    participant Elig as Eligibility Engine
    participant W as Document Wallet
    participant AD as Gov Adapter
    participant GOV as Scholarship Portal

    S->>App: Register / Login
    App->>API: POST /auth/login
    S->>App: Create unified profile
    App->>API: PUT /profile
    API->>API: Verify (e-KYC / record match)
    S->>App: Check eligibility
    App->>API: POST /eligibility/evaluate
    API->>Elig: Profile + rules
    Elig-->>API: Eligible schemes + reasons
    S->>App: Select scheme and apply
    App->>API: POST /applications
    API->>W: Fetch consented documents
    API->>AD: Map canonical profile to scheme schema
    AD->>GOV: Submit via authorized API
    loop Status sync
        AD->>GOV: Poll / webhook
        AD-->>API: Verification / Deficiency / Sanction / DBT
        API-->>S: Push / SMS / WhatsApp
    end
```

---

## 🧰 Technology Stack

| Layer | Technologies |
|-------|--------------|
| Mobile frontend | Flutter (Android / iOS) |
| Web access | Lightweight PWA / web portal |
| Backend | Python, FastAPI |
| Primary database | PostgreSQL |
| Local storage | SQLite |
| Cache / rate limiting | Redis |
| AuthN / AuthZ | OAuth 2.0, JWT, RBAC |
| ML | Isolation Forest, XGBoost |
| Record matching | Probabilistic linkage, fuzzy matching |
| Assistant | LLM + RAG |
| Translation | IndicTrans2 |
| Notifications | Firebase Cloud Messaging |
| Messaging | Twilio SMS, WhatsApp API |
| Documents | DigiLocker |
| Security | TLS 1.3, AES-256, audit logs |

---

## 🧠 AI/ML Design

> **Rule:** ML assists reviewers. It never independently decides eligibility or sanction.

### 1. Eligibility (rule-based, not ML)

```mermaid
flowchart LR
    P[Student Profile] --> R[Government-Defined Rules]
    R --> EE[Eligibility Engine]
    EE --> O[Eligible Schemes + Explanations]
```

Rules are stored as versioned configuration so they can be updated when policy changes, without code changes.

```python
# backend/services/eligibility.py (illustrative)
from dataclasses import dataclass
from typing import Callable

@dataclass(frozen=True)
class Rule:
    id: str
    scheme: str
    description: str
    check: Callable[[dict], bool]

RULES = [
    Rule("PM_INCOME", "Post-Matric",
         "Annual family income within scheme ceiling",
         lambda p: p["income"] <= p["scheme_params"]["income_ceiling"]),
    Rule("ST_CERT", "Post-Matric",
         "Valid ST certificate present",
         lambda p: p["st_certificate_verified"]),
]

def evaluate(profile: dict, scheme: str) -> dict:
    results = [(r.id, r.description, r.check(profile))
               for r in RULES if r.scheme == scheme]
    return {
        "scheme": scheme,
        "eligible": all(ok for *_, ok in results),
        "explanations": [{"rule": i, "desc": d, "passed": ok} for i, d, ok in results],
    }
```

### 2. Cross-system record matching

```mermaid
flowchart LR
    A[Records from authorized sources] --> B[Attribute extraction]
    B --> C[Probabilistic + fuzzy matching]
    C --> D[Match confidence]
    D -->|High| E[Verified]
    D -->|Low / ambiguous| F[Review required]
```

- Blocking on stable keys to limit comparisons
- Fuzzy string similarity on names, institution, address
- Probabilistic (Fellegi–Sunter style) weighting across attributes

### 3. Anomaly detection

```mermaid
flowchart LR
    A[Application & verification data] --> B[Feature processing]
    B --> C[Isolation Forest]
    C --> D[Risk / anomaly flag]
    D --> E[Authorized human review]
```

### 4. Verification confidence

XGBoost scores verification confidence to **prioritize** the reviewer queue.

### 5. JAGO assistant (LLM + RAG + IndicTrans2)

```mermaid
flowchart LR
    Q[Student query in regional language] --> T1[IndicTrans2 → English]
    T1 --> CTX[Fetch student context: status, deficiencies, pending docs]
    CTX --> RAG[Retrieve scheme guidelines]
    RAG --> LLM[LLM response]
    LLM --> T2[IndicTrans2 → student language]
    T2 --> A[Answer + next steps]
```

---

## 📱 Offline-First Architecture

```mermaid
flowchart TD
    U[Student updates application] --> N{Internet?}
    N -->|Yes| SY[Sync to API] --> PG[(PostgreSQL)]
    N -->|No| L[(SQLite)] --> Q[Local sync queue]
    Q --> R[Connection restored]
    R --> SB[Sync to backend]
```

**Sync guarantees (design targets)**

- Every local write gets a client-generated UUID and a monotonic version
- Server operations are **idempotent** (replay-safe)
- Conflicts resolved with field-level, version-aware merge; unresolvable conflicts surface to the user
- Queue persisted in SQLite, drained with exponential backoff

---

## 🗃️ Data Model (core entities)

```mermaid
erDiagram
    STUDENT ||--|| PROFILE : has
    STUDENT ||--o{ DOCUMENT : owns
    STUDENT ||--o{ APPLICATION : submits
    SCHEME  ||--o{ APPLICATION : receives
    SCHEME  ||--o{ ELIGIBILITY_RULE : defined_by
    APPLICATION ||--o{ STATUS_EVENT : tracks
    APPLICATION ||--o{ DEFICIENCY : may_have
    APPLICATION ||--o| DBT_RECORD : results_in
    STUDENT ||--o{ CONSENT : grants
    APPLICATION ||--o{ ANOMALY_FLAG : may_raise
    USER ||--o{ AUDIT_LOG : generates
```

---

## 🔌 API Surface (Planned)

Base path: `/api/v1` · Auth: `Authorization: Bearer <JWT>`

| Method | Endpoint | Purpose |
|--------|----------|---------|
| `POST` | `/auth/register` | Register student |
| `POST` | `/auth/login` | OAuth 2.0 / JWT login |
| `GET` / `PUT` | `/profile` | Read / update unified profile |
| `POST` | `/eligibility/evaluate` | Evaluate eligible schemes |
| `GET` | `/schemes` | Browse supported schemes |
| `POST` | `/applications` | Create application |
| `GET` | `/applications/{id}` | Application detail + timeline |
| `GET` | `/applications/{id}/dbt` | DBT / payment status |
| `POST` | `/documents` | Upload to wallet |
| `POST` | `/documents/digilocker/link` | Link DigiLocker (consent flow) |
| `POST` | `/sync/push` | Offline queue push (idempotent) |
| `POST` | `/jago/chat` | Assistant query |
| `GET` | `/admin/analytics` | Admin dashboards |
| `GET` | `/admin/coverage-gaps` | Potential coverage gaps |
| `GET` | `/admin/flags` | Anomaly / risk flags for review |

**Example**

```http
POST /api/v1/eligibility/evaluate
Content-Type: application/json
Authorization: Bearer <token>

{ "student_id": "stu_123", "schemes": ["PRE_MATRIC", "POST_MATRIC", "TOP_CLASS"] }
```

```json
{
  "results": [
    {
      "scheme": "POST_MATRIC",
      "eligible": true,
      "explanations": [
        { "rule": "ST_CERT", "desc": "Valid ST certificate present", "passed": true },
        { "rule": "PM_INCOME", "desc": "Income within ceiling", "passed": true }
      ]
    }
  ],
  "conflicts": []
}
```

---

## 🔗 Proposed Integrations

| System | Purpose |
|--------|---------|
| NSP / OTR | Scholarship application and status |
| SFMP | Fellowship workflows |
| NOS | National Overseas Scholarship |
| DigiLocker | Document verification and reuse |
| UIDAI / e-KYC | Identity verification |
| APAAR | Academic identity |
| AISHE | Higher-education institution data |
| UDISE+ | School-education data |
| State e-District | Certificates (caste / income) |
| UGC-NTA | Where applicable |

Each integration is implemented as an **adapter** with:

```
Adapter
 ├── authenticate()
 ├── map_profile(canonical) -> scheme_payload
 ├── submit(payload)
 ├── fetch_status(ref)
 └── normalize_status(raw) -> LifecycleState
```

Failures flow through **retry queues → Dead Letter Queues (DLQ)** with controlled exception handling.

---

## 🔐 Security & Privacy

| Control | Implementation |
|---------|----------------|
| Authentication | OAuth 2.0, JWT (short-lived access + refresh) |
| Authorization | Role-Based Access Control (Student / Reviewer / Admin) |
| In transit | TLS 1.3 |
| At rest | AES-256 |
| Data sharing | Explicit, revocable consent records |
| Traceability | Immutable audit logs |
| Input safety | Schema validation (Pydantic) |
| Abuse protection | Redis-backed rate limiting |
| Resilience | Retry queues, DLQs |
| AI governance | Human review required for all anomaly / risk flags |

---

## 📦 Project Structure

```
JanjatiSetu/
├── frontend/
│   ├── mobile/                 # Flutter app (student + admin)
│   └── web/                    # PWA / web portal
├── backend/
│   ├── api/                    # FastAPI routers
│   ├── models/                 # SQLAlchemy / Pydantic models
│   ├── services/               # Business logic
│   ├── integrations/           # Government adapters
│   └── auth/                   # OAuth2, JWT, RBAC
├── ai_ml/
│   ├── eligibility/            # Rule engine
│   ├── matching/               # Record linkage
│   ├── anomaly_detection/      # Isolation Forest
│   ├── verification/           # XGBoost confidence
│   └── jago/                   # LLM + RAG + IndicTrans2
├── database/
│   ├── migrations/
│   └── schemas/
├── docs/
│   ├── architecture/
│   ├── workflows/
│   ├── proof_documents/
│   └── screenshots/
├── tests/
├── README.md
└── LICENSE
```

> Exact layout may differ depending on the implementation in the repository.

---

## 🚀 Quick Start

### Prerequisites

- Python 3.11+
- Flutter 3.x (stable)
- PostgreSQL 15+
- Redis 7+
- Docker & Docker Compose (optional)

### 1. Clone

```bash
git clone https://github.com/<your-org>/JanjatiSetu.git
cd JanjatiSetu
```

### 2. Environment

```bash
cp .env.example .env
```

```env
# Core
APP_ENV=development
SECRET_KEY=change-me
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30

# Data stores
DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/janjatisetu
REDIS_URL=redis://localhost:6379/0

# Integrations (sandbox / mock by default)
USE_MOCK_ADAPTERS=true
DIGILOCKER_CLIENT_ID=
DIGILOCKER_CLIENT_SECRET=

# Notifications
FCM_CREDENTIALS_PATH=
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
WHATSAPP_API_TOKEN=

# AI
LLM_API_KEY=
INDICTRANS2_MODEL_PATH=
```

### 3. Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
alembic upgrade head
uvicorn api.main:app --reload --port 8000
```

Interactive docs: `http://localhost:8000/docs`

### 4. Mobile app

```bash
cd frontend/mobile
flutter pub get
flutter run
```

### 5. Docker (all services)

```bash
docker compose up --build
```

---

## 🧪 Testing

```bash
# Backend
pytest tests/ -v --cov=backend

# Flutter
cd frontend/mobile && flutter test
```

Suggested test layers: rule-engine unit tests, adapter contract tests (against mocks), sync-queue idempotency tests, and RBAC permission tests.

---

## 📊 Existing Workflow vs JanjatiSetu

| Existing workflow | JanjatiSetu |
|-------------------|-------------|
| Multiple scholarship portals | Single-window experience |
| Search multiple sources | Unified scheme discovery |
| Manually interpret eligibility | Rule-based eligibility check |
| Re-enter information | Reuse unified profile |
| Repeated document submission | Document wallet |
| Limited cross-system visibility | Status synchronization |
| Difficult payment tracking | DBT tracking |
| Limited multilingual help | JAGO assistant |
| Connectivity interrupts work | Offline-first |
| Fragmented monitoring | Admin dashboard and analytics |

---

## 📈 Impact

| Students | Administrators | Society |
|----------|----------------|---------|
| Reduced complexity and dropouts | Less repetitive verification | Better scholarship accessibility |
| Clear deficiencies and next steps | Cross-system visibility | Greater awareness among eligible students |
| Multilingual support | Coverage-gap analysis | Inclusive multilingual access |
| Works in remote areas | Audit-ready traceability | Support for remote communities |

---

## ⚠️ Challenges & Mitigation

| Challenge | Strategy |
|-----------|----------|
| Limited digital literacy | Simple multilingual UI, JAGO guidance |
| Poor connectivity | SQLite offline-first sync |
| Sensitive data | RBAC, encryption, TLS, consent, audit logs |
| Data mismatch | Verification and record matching |
| Adoption resistance | Simple onboarding, capacity building |
| Coverage-gap uncertainty | Validate potential cases before outreach |
| Integration complexity | Authorized APIs, data-sharing agreements, phased rollout |
| Fragmented systems | Common API integration layer |

> A missing scholarship record does **not** by itself prove eligibility. Potential cases must be validated against rules and available records.

---

## 🧭 Feasibility

- **Technical:** adapter-based integration over existing APIs; no changes to current portals
- **Operational:** modular services deployable in phases
- **Economic:** reusable profiles and document reuse cut manual effort
- **Sustainable:** new schemes, states and sources added via adapters
- **Scalable:** controlled district-level pilot, then state and department expansion

---

## 🗺️ Roadmap

- [x] Problem analysis and architecture design
- [x] Unified lifecycle and canonical profile model
- [ ] Core backend: auth, profile, schemes, applications
- [ ] Rule-based eligibility engine with conflict detection
- [ ] Document wallet + DigiLocker consent flow
- [ ] Offline-first sync (SQLite queue) and PWA
- [ ] Record matching and anomaly detection pipeline
- [ ] JAGO assistant (LLM + RAG + IndicTrans2)
- [ ] Admin portal: analytics, coverage gaps, review queue
- [ ] Multichannel notifications (FCM, SMS, WhatsApp)
- [ ] Pilot in selected districts

**Future scope:** more schemes and states, additional authorized data sources, voice assistance, expanded analytics, more notification channels, nationwide scaling.

---

## 📚 References

**Research**
- E-Government Interoperability — Policy, Management & Technology Dimensions
- E-Government Integration and Interoperability
- Interoperability in E-Government
- Maturity Levels for Interoperability in Digital Government
- Interorganizational Information Integration

**Government**
- National Scholarship Portal (NSP)
- National Overseas Scholarship (NOS)
- Common Fellowships Portal

---

## 📹 Demo & Screenshots

**📂 Project photos & demo:** [View on Google Drive](https://drive.google.com/drive/folders/1NnERBInafUssYlbytyvxmCdMt7t9qtMw?usp=sharing)
---

## 🏆 Smart India Hackathon 2026

| | |
|---|---|
| **Project** | JanjatiSetu |
| **Team** | Unique Thing |
| **Event** | Smart India Hackathon 2026 |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Implement your changes
4. Run tests
5. Commit: `git commit -m "feat: add your feature"`
6. Push and open a Pull Request

---

## ⚖️ Disclaimer

JanjatiSetu is a proposed/prototype solution. Government-system integrations, eligibility rules, data access, identity verification and scholarship decisions require appropriate authorization, official APIs, applicable policies and agreements with the concerned authorities.

AI/ML components assist verification and administrative workflows. They must not independently make scholarship sanction or eligibility decisions outside approved government rules and processes.

---

<div align="center">

### 👥 Team Unique Thing

*Building technology for a more accessible, transparent, and unified scholarship ecosystem for tribal students.*

**JanjatiSetu — One Platform. Multiple Schemes. Brighter Futures.** 🌱

</div>
