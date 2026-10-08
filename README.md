JanjatiSetu 🌱
Unified Scholarship Platform for Tribal Students
One Platform. Multiple Schemes. Brighter Futures.

JanjatiSetu is a proposed mobile-first unified scholarship orchestration platform designed to simplify access to tribal student scholarships and fellowships by bringing fragmented scholarship workflows into a single digital experience.
The platform is designed to integrate authorized government scholarship systems and data sources through secure APIs and adapters, provide a unified student profile, automate eligibility checks, support document reuse, track application and DBT status, and provide multilingual assistance.
🎯 Problem
Tribal students may need to navigate multiple scholarship portals and processes for different schemes. This can result in:
- Multiple portals and fragmented workflows
- Repeated entry of the same student information
- Repeated document submission and verification
- Difficulty understanding eligibility criteria
- Limited visibility into application, deficiency, sanction, and payment status
- Connectivity challenges in remote areas
- Language and digital-literacy barriers
- Data mismatches across different systems
JanjatiSetu addresses these challenges through a unified scholarship access and orchestration layer.
💡 Proposed Solution
JanjatiSetu provides a single-window scholarship experience for tribal students.
The platform follows a unified application lifecycle:
Applied → Verification → Deficiency → Correction → Sanction → DBT
Students can create one verified profile and reuse eligible information across scholarship applications instead of repeatedly entering the same details.
The platform is designed around:
- Unified Scholarship Dashboard
- Unified Student Profile
- Multi-Scheme Eligibility Engine
- Document Wallet
- Application & DBT Tracking
- Cross-System Verification
- AI-Assisted Anomaly Detection
- Multilingual JAGO Assistant
- Offline-First Support
- Admin Coverage-Gap Intelligence
- Secure Government API Integration
🚀 Key Features
1. Unified Scholarship Dashboard
Provides a single view of applications across supported scholarship systems.
Students can view:
- Application status
- Verification status
- Deficiencies
- Corrections required
- Sanction status
- DBT/payment information
2. Unified Student Profile
Creates a 360° scholarship profile containing verified information such as:
- Identity
- ST/PVTG information
- Academic details
- Institution details
- Income information
- Bank information
- Scheme-related attributes
A schema-mapping layer converts the canonical profile into the format required by individual scholarship systems.
Benefits:
- One-time data entry
- Automatic form pre-filling
- Consistency validation
- Reuse of verified information
3. Multi-Scheme Eligibility & Conflict Detection
A configurable rule-based engine applies government-defined eligibility criteria.
It is designed to identify:
- Eligible scholarship schemes
- Duplicate benefits
- Concurrent applications
- Scholarship conflicts
Eligibility decisions are intended to remain:
- Deterministic
- Explainable
- Auditable
4. Document Wallet 📄
A consent-based document wallet is designed for secure document reuse.
The proposed integration includes DigiLocker for document verification and reuse.
Students can prepare applications even during low or intermittent connectivity, with changes stored locally and synchronized when connectivity is restored.
5. Cross-System Verification & AI Anomaly Detection
The platform uses multi-source entity resolution and record matching to identify potential:
- Duplicate records
- Data inconsistencies
- Unusual patterns
- Cross-system mismatches
The proposed AI/ML layer includes:
- Probabilistic record linkage
- Fuzzy matching
- Isolation Forest for anomaly detection
- XGBoost for verification confidence
AI-generated flags are intended to support authorized human review and are not designed to automatically make sanction decisions.

6. JAGO Multilingual Scholarship Assistant 🤖
JAGO is the proposed multilingual scholarship assistant.
It uses an:
LLM + RAG + IndicTrans2
approach to provide scholarship-related assistance.
JAGO is designed to understand the student's:
- Current application status
- Pending actions
- Deficiencies
- Required documents
- Next steps
It can provide multilingual guidance and notifications for scholarship-related workflows.
7. Offline-First Architecture 📱
JanjatiSetu is designed for environments with poor or intermittent internet connectivity.
The proposed architecture uses:
- SQLite for local storage
- Local synchronization queue
- Offline application preparation
- Automatic synchronization when connectivity returns
A lightweight PWA is also proposed for basic-device and low-bandwidth access.
8. Admin Coverage-Gap Intelligence
The admin platform can use authorized education records to identify potential students who may not have corresponding scholarship records.
The system can support:
- Coverage-gap detection
- Validation of potential cases
- Targeted outreach
- Reports and analytics
A missing scholarship record does not by itself prove eligibility. Potential cases require validation against eligibility rules and available records.

9. Notifications & Multichannel Outreach
The proposed notification architecture includes:
- Firebase Cloud Messaging (FCM) for push notifications
- Twilio for SMS
- WhatsApp API for milestone alerts and outreach
Students can receive reminders and updates regarding application milestones, deficiencies, sanctions, and DBT.
👥 User Roles
Student Portal
Students can:
- Create and manage their unified profile
- Check scholarship eligibility
- Browse supported schemes
- Apply for scholarships
- Upload/reuse documents
- Track application status
- Track DBT/payment status
- Receive notifications
- Get multilingual assistance through JAGO
Ministry / Admin Portal
Authorized officials can:
- Monitor sanctions and DBT
- View scholarship analytics
- Detect potential coverage gaps
- Plan targeted outreach
- Review anomaly/risk flags
- Generate reports
- Monitor applications across supported schemes
🏗️ System Architecture
                         ┌──────────────────────────┐
                         │      User Devices        │
                         │ Android / iOS / Web-PWA  │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │   Flutter Application    │
                         │ Student / Admin Portal   │
                         └────────────┬─────────────┘
                                      │
                                      ▼
                         ┌──────────────────────────┐
                         │      FastAPI Backend     │
                         │     Python REST APIs     │
                         └───────┬─────────┬────────┘
                                 │         │
                ┌────────────────┘         └─────────────────┐
                ▼                                            ▼
     ┌──────────────────────┐                     ┌──────────────────────┐
     │ AI / ML Service Layer│                     │ Integration &        │
     │                      │                     │ Document Wallet      │
     │ • Eligibility        │                     │                      │
     │ • Record Matching    │                     │ • API Gateway        │
     │ • Coverage Gap       │                     │ • Identity Matching  │
     │ • Anomaly Detection  │                     │ • Document Wallet    │
     │ • Verification       │                     │ • Verification       │
     │ • JAGO Chatbot       │                     │ • Status Sync        │
     └──────────┬───────────┘                     └──────────┬───────────┘
                │                                            │
                └────────────────────┬───────────────────────┘
                                     ▼
                         ┌──────────────────────────┐
                         │ Government Data Sources  │
                         │                          │
                         │ NSP / OTR                │
                         │ SFMP                     │
                         │ NOS                      │
                         │ DigiLocker               │
                         │ UIDAI / e-KYC            │
                         │ APAAR                    │
                         │ AISHE                    │
                         │ UDISE+                   │
                         └──────────────────────────┘

                         ┌──────────────────────────┐
                         │ PostgreSQL Database      │
                         │ Application & Student    │
                         │ Transactional Data       │
                         └──────────────────────────┘
🛠️ Technology Stack
Layer	Technologies
Mobile Frontend	Flutter
Web Access	Lightweight PWA / Web Portal
Backend	FastAPI, Python
Database	PostgreSQL
Local Storage	SQLite
Caching / Rate Limiting	Redis
Authentication	OAuth 2.0, JWT, RBAC
AI/ML	Isolation Forest, XGBoost
Record Matching	Probabilistic Matching, Fuzzy Matching
NLP / Assistant	LLM + RAG
Translation	IndicTrans2
Notifications	Firebase Cloud Messaging
Communication	Twilio SMS / WhatsApp API
Document Integration	DigiLocker
Security	TLS 1.3, AES-256, Audit Logs


🔗 Proposed Integrations
The technical architecture proposes secure adapter-based integration with authorized systems and data sources, including:
- National Scholarship Portal (NSP / OTR)
- SFMP
- National Overseas Scholarship (NOS)
- DigiLocker
- UIDAI / e-KYC
- APAAR
- AISHE
- UDISE+
- State e-District systems
- UGC-NTA where applicable
The integration layer is designed to avoid unnecessary changes to existing scholarship portals by using APIs and adapters.
🔐 Security & Privacy
JanjatiSetu follows a security-by-design approach.
Proposed controls include:
- OAuth 2.0
- JWT authentication
- Role-Based Access Control (RBAC)
- TLS 1.3 for data in transit
- AES-256 encryption for data at rest
- Consent-based document/data sharing
- Audit logging
- Schema validation
- Retry queues
- Dead Letter Queues (DLQs)
- Controlled exception handling
- Human review for anomaly/risk flags
Government integrations are intended to operate only through authorized APIs, permissions, and applicable data-sharing arrangements.
🔄 Application Workflow
Student
   │
   ▼
Login / Registration
   │
   ▼
Create Unified Profile
   │
   ▼
Verify Student Information
   │
   ▼
Check Eligibility
   │
   ├──────────────► View Eligible Schemes
   │
   ▼
Select Scholarship
   │
   ▼
Reuse Profile & Documents
   │
   ▼
Guided Application
   │
   ▼
Submit to Relevant Government Portal
   │
   ▼
Application Status Synchronization
   │
   ▼
Verification
   │
   ├── Deficiency ──► Correction ──► Re-verification
   │
   ▼
Sanction
   │
   ▼
DBT / Payment Tracking
   │
   ▼
Student Notification
🧠 AI/ML Architecture
Eligibility Matching
Student Profile
      ↓
Government-Defined Rules
      ↓
Eligibility Engine
      ↓
Eligible Schemes
Cross-System Record Matching
Records from Authorized Sources
              ↓
     Attribute Extraction
              ↓
 Probabilistic / Fuzzy Matching
              ↓
       Match Confidence
              ↓
 Verified / Review Required
Anomaly Detection
Application & Verification Data
              ↓
      Feature Processing
              ↓
       Isolation Forest
              ↓
        Risk / Anomaly Flag
              ↓
     Authorized Human Review
Verification Confidence
The proposed architecture includes XGBoost-based verification confidence scoring to assist authorized verification workflows.
🌐 Offline-First Flow
Student Updates Application
          ↓
      Internet?
      /       \
    YES        NO
     ↓          ↓
Sync to API   Store in SQLite
     ↓          ↓
PostgreSQL    Local Sync Queue
                  ↓
             Connection Restored
                  ↓
             Sync to Backend
This approach allows students to prepare and update applications even when connectivity is unreliable.
📊 Existing Workflow vs JanjatiSetu
Existing Workflow	JanjatiSetu
Multiple scholarship portals	Single-window experience
Search multiple sources	Unified scheme discovery
Manually understand eligibility	Rule-based eligibility check
Re-enter information	Reuse unified profile
Repeated document submission	Document wallet and reuse
Limited cross-system visibility	Status synchronization
Difficult payment tracking	DBT tracking
Limited multilingual assistance	JAGO multilingual assistant
Connectivity can interrupt workflow	Offline-first support
Fragmented monitoring	Admin dashboard and analytics


🌟 What Makes JanjatiSetu Unique?
1. Single-Window Scholarship Access
One platform for accessing multiple tribal scholarship and fellowship workflows.
2. One-Time Data, Multiple Applications
A unified profile reduces repetitive data entry.
3. Rule-Based Eligibility & Conflict Detection
Government-defined rules provide deterministic and explainable eligibility evaluation.
4. Cross-System Verification & Anomaly Detection
Record matching and anomaly detection help authorized officials identify inconsistencies and potential duplicates.
5. Multilingual Scholarship Assistant
JAGO provides personalized scholarship guidance using multilingual NLP/RAG capabilities.
6. Multichannel Outreach
The proposed system supports push notifications, SMS, and WhatsApp-based alerts.
7. Offline-First Access
Students can prepare applications during low-connectivity conditions and synchronize later.
8. Coverage-Gap Intelligence
Authorized records can be analyzed to identify potential scholarship coverage gaps for validation and targeted outreach.
📈 Impact & Benefits
Student Impact
- Greater student empowerment
- Reduced application complexity
- Reduced application dropouts
- Faster access to scholarship information
- Better understanding of deficiencies and next steps
- Multilingual support
- Improved access in remote/low-connectivity areas
Administrative Benefits
- Reduced repetitive verification and data entry
- Better application visibility
- Cross-system monitoring
- Coverage-gap analysis
- Targeted outreach
- Reports and analytics
- Better traceability through audit logs
Social Impact
- Improved scholarship accessibility
- Better awareness among eligible students
- Support for students in remote areas
- More inclusive multilingual access
⚠️ Challenges & Mitigation
Challenge	Proposed Strategy
Limited digital literacy	Simple multilingual UI and JAGO guidance
Poor connectivity	Offline-first SQLite and synchronization
Sensitive scholarship data	RBAC, encryption, TLS, consent and audit logging
Data mismatch	Verification and record matching
Adoption resistance	Simple onboarding and capacity building
Coverage-gap uncertainty	Validate potential cases before outreach
Government integration complexity	Authorized APIs, data-sharing agreements and phased integration
Fragmented systems	Common API integration layer


📦 Project Structure
A suggested repository structure:
JanjatiSetu/
│
├── frontend/
│   ├── mobile/
│   └── web/
│
├── backend/
│   ├── api/
│   ├── models/
│   ├── services/
│   ├── integrations/
│   └── auth/
│
├── ai_ml/
│   ├── eligibility/
│   ├── matching/
│   ├── anomaly_detection/
│   ├── verification/
│   └── jago/
│
├── database/
│   ├── migrations/
│   └── schemas/
│
├── docs/
│   ├── architecture/
│   ├── workflows/
│   └── proof_documents/
│
├── tests/
│
├── README.md
└── LICENSE
The exact directory structure may differ depending on the implementation in the repository.

🧪 Feasibility & Viability
Technical Feasibility
The proposed solution uses existing digital infrastructure, APIs, and secure adapter-based integrations rather than requiring changes to existing scholarship portals.
Operational Feasibility
The platform is modular, allowing components such as the dashboard, profile/document wallet, verification, JAGO, and analytics to be deployed in phases.
Economic Feasibility
Reusable profiles, automated validation, and document reuse can reduce repetitive manual work and data-entry effort.
Sustainable Feasibility
The modular architecture allows additional scholarship schemes, states, and authorized data sources to be integrated through adapters.
Scalability
The proposed platform can begin with a controlled pilot in selected districts and progressively scale across states and departments after validating workflows and interoperability.
🔮 Future Scope
Potential future expansion includes:
- Additional scholarship schemes
- More state-level integrations
- More authorized government data sources
- Advanced multilingual and voice assistance
- Expanded analytics and dashboards
- Wider coverage-gap intelligence
- Additional notification channels
- Scaled deployment across states and departments
📚 Research & References
The proposal references research areas including:
- E-Government Interoperability — Policy, Management & Technology Dimensions
- E-Government Integration and Interoperability
- Interoperability in E-Government
- Maturity Levels for Interoperability in Digital Government
- Interorganizational Information Integration
Government references mentioned in the proposal include:
- National Scholarship Portal (NSP)
- National Overseas Scholarship (NOS)
- Common Fellowships Portal
🏆 Smart India Hackathon
Project: JanjatiSetu
Team: Unique Thing
Event: Smart India Hackathon 2026
JanjatiSetu is proposed as a unified digital scholarship ecosystem for tribal students, focusing on accessibility, interoperability, transparency, multilingual assistance, and reduced administrative complexity.
📹 Demo
Add your project demonstration link here:
Demo Video: [ADD YOUR DEMO LINK]
📸 Screenshots
Add screenshots of the following modules to showcase the prototype:
- Student Dashboard
- Unified Profile
- Eligibility Checker
- Scholarship Application
- Document Wallet
- Application Tracking
- DBT Tracking
- JAGO Assistant
- Admin Dashboard
- Coverage-Gap Analytics
Example:
docs/screenshots/
├── student-dashboard.png
├── unified-profile.png
├── eligibility.png
├── application-tracking.png
├── jago-assistant.png
└── admin-dashboard.png
🤝 Contribution
Contributions and suggestions are welcome.
1. Fork the repository
2. Create a feature branch
3. Implement your changes
4. Test the changes
5. Commit your changes
6. Open a Pull Request
⚖️ Disclaimer
JanjatiSetu is a proposed/prototype solution. Government-system integrations, eligibility rules, data access, identity verification, and scholarship decisions would require appropriate authorization, official APIs, applicable policies, and agreements with the concerned authorities.
AI/ML components are intended to assist verification and administrative workflows. They should not independently make scholarship sanction or eligibility decisions outside approved government rules and processes.
👥 Team Unique Thing
Building technology for a more accessible, transparent, and unified scholarship ecosystem for tribal students.
JanjatiSetu — One Platform. Multiple Schemes. Brighter Futures.
