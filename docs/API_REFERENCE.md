# JanjatiSetu API Reference

Base URL: `http://localhost:8000/api/v1`
Auth: `Authorization: Bearer <token>` (obtained from `POST /auth/login`)
Interactive docs (Swagger UI) are also served live at `/docs` when the backend is running.

---

## Auth

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/auth/register` | — | Create a new student account. Body: `{phone, password, full_name, email?, language?}` |
| POST | `/auth/login` | — | OAuth2 password flow. Form fields: `username` (phone), `password`. Returns `{access_token, token_type, role, user_id, full_name, language}` |
| GET | `/auth/me` | any | Current user's identity |

## Profile

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/profile` | student | Full profile, including completeness % |
| PUT | `/profile` | student | Partial update. `aadhaar_number` / `bank_account_number`, if sent, are hashed/encrypted and never stored or echoed back in the clear |
| GET | `/profile/consents` | student | List of consent purposes and whether each is granted |
| PUT | `/profile/consents` | student | `{purpose, granted}` — one of `DIGILOCKER, UIDAI, APAAR, ENROLMENT, EDISTRICT, UGC_NTA` |
| POST | `/profile/verify` | student | Re-run cross-source verification now (also runs automatically on submission). Returns the verification report |
| PUT | `/profile/language` | student | `{language}` — `en` or `hi` |
| PUT | `/profile/fcm-token` | student | Register a device token for push notifications |

## Eligibility & dashboard

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/eligibility` | student | Per-scheme eligibility (`ELIGIBLE` / `NEEDS_REVIEW` / `NOT_ELIGIBLE`) with the reasons and any missing fields |
| GET | `/dashboard` | student | One view: applications with timelines, the single most useful `next_step`, and totals |

## Wallet (documents)

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/wallet/digilocker` | student | List documents available in DigiLocker (requires the `DIGILOCKER` consent) |
| POST | `/wallet/import` | student | `{uri}` — import one DigiLocker document into the wallet |
| POST | `/wallet/upload` | student | Multipart: `doc_type` (form field) + `file` (PDF/JPG/PNG, max `MAX_UPLOAD_MB`) |
| GET | `/wallet/documents` | student | All documents in the wallet |
| DELETE | `/wallet/documents/{id}` | student | Remove a document (blocked if attached to a submitted application) |
| POST | `/wallet/documents/{id}/use` | student | Attach a wallet document to a draft application; auto-fills matching form fields |

## Applications

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/applications` | student | `{scheme_code, academic_year?, client_uuid?}` — creates (or returns the existing) draft |
| GET | `/applications/{id}` | student | Full detail: form data, documents, events, deficiencies, timeline |
| PUT | `/applications/{id}` | student | Update `form_data` / `document_ids` while editable (`DRAFT` or `DEFICIENCY`) |
| POST | `/applications/{id}/submit` | student | Validates documents + eligibility, pushes to the scheme's portal, opens verification |
| GET | `/applications/{id}/timeline` | student | Just the 5-stage timeline and raw events |
| POST | `/applications/{id}/deficiencies/{def_id}/resolve` | student | `{note, document_id?}` — submit a correction |

## Notifications

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/notifications` | student | `?unread_only=true&limit=50` |
| GET | `/notifications/unread-count` | student | `{unread}` |
| POST | `/notifications/{id}/read` | student | Mark one as read |
| POST | `/notifications/read-all` | student | Mark all as read |

## JAGO assistant

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/assistant/chat` | student | `{message}` — bilingual (English/Hindi) reply grounded in the student's own data, plus follow-up `suggestions` |

## Offline sync

| Method | Path | Auth | Description |
|---|---|---|---|
| POST | `/sync/push` | student | `{operations: [{op_id, type, application_id?, client_uuid?, payload}]}`. Idempotent by `op_id`; a retried batch never duplicates work |
| GET | `/sync/pull` | student | `?since=<ISO datetime>` — profile, applications, documents, eligibility, schemes and recent notifications in one call |

Sync operation `type` values: `CREATE_APPLICATION`, `UPDATE_APPLICATION`, `SUBMIT_APPLICATION`, `UPDATE_PROFILE`.
A push result is one of: `{ok: true, ...}`, `{ok: false, error: "CONFLICT", application}` (the application moved past `DRAFT`/`DEFICIENCY` since the edit was queued — the server copy wins), `{ok: false, error: "NOT_FOUND"}`, or `{ok: false, error: "REJECTED_BY_RULES", detail}`.

## Ministry admin (VERIFIER / ADMIN roles)

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/admin/overview` | staff | Application counts by status/scheme, open exception counts, money sanctioned/paid |
| GET | `/admin/applications` | staff | `?status=&scheme=&district=&q=&limit=&offset=` — submitted applications only |
| GET | `/admin/applications/{id}` | staff | Full detail with masked student identifiers, documents, and open cases |
| POST | `/admin/applications/{id}/action` | staff | `{action, note?, doc_type?, amount?, utr?}` — one of `START_REVIEW, RAISE_DEFICIENCY, VERIFY, SANCTION, PAY, REJECT, RETRY_PUSH`. `VERIFY` is blocked while exception cases are open. `REJECT` requires `note`. |
| GET | `/admin/exceptions` | staff | `?status=OPEN&kind=` — reviewable cases, most severe first |
| POST | `/admin/exceptions/{id}/resolve` | staff | `{resolution, note?}` — `resolution` one of `CONFIRMED_OK, CORRECTED, DISMISS, ESCALATE` |
| POST | `/admin/coverage-gap/run` | admin | Re-match every enrolled ST record against scholarship records; returns the funnel |
| GET | `/admin/coverage-gap/summary` | admin | Funnel totals (incl. `ready_for_outreach`; `outreach_sent` counts gaps actually contacted) + top districts by open gaps |
| GET | `/admin/coverage-gap` | admin | `?state=&district=&limit=&offset=` — individual gap records; `state` is one of `POTENTIAL_GAP, VALIDATED, OUTREACH_SENT, APPLIED, DISMISSED`. Each item includes the latest `outreach_channel` / `outreach_status` |
| POST | `/admin/coverage-gap/outreach` | admin | `{gap_ids, channel, message?}` — `channel` one of `JAGO, SMS, APP, INSTITUTION`. Only `VALIDATED` gaps are contacted, once. Returns `{sent, skipped, delivered, queued, undelivered}`: `delivered` reached the student, `queued` is recorded for an institution's nodal officer, `undelivered` could not be sent (student not registered, no mobile number, SMS disabled) |
| POST | `/admin/coverage-gap/{id}/resolve` | admin | `{action, note?}` — `DISMISS` (needs `note`; from `POTENTIAL_GAP`/`VALIDATED`/`OUTREACH_SENT`), `MARK_APPLIED` (student applied outside JanjatiSetu; same source states), `REOPEN` (from `DISMISSED`/`OUTREACH_SENT`/`APPLIED`; re-validates, so an undelivered case can be retried on another channel). 400 if `DISMISS` has no note, 409 if the action isn't valid from the current state. Returns the updated gap |
| GET | `/admin/audit` | admin | Recent audit log entries |

## Meta

| Method | Path | Description |
|---|---|---|
| GET | `/health` | `{status: "ok", integration_mode}` — no auth |

---

## Errors

Standard FastAPI/Pydantic shapes: `{"detail": "message"}` for most errors, or `{"detail": {...}}` where the endpoint needs structured detail (e.g. `POST /applications/{id}/submit` returns `{"detail": {"missing_documents": [...], "message": "..."}}`). `WorkflowError` (an illegal status transition) always returns HTTP 409.

## Demo accounts

See the README for the full list of demo phone numbers/passwords and what each account demonstrates.
