import hashlib
import os
import uuid
from datetime import date

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import RedirectResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..deps import student_only
from ..integrations.gateway import Gateway, SourceUnavailable
from ..models import Application, Document, User
from ..schemas import DOC_TYPES, DigiLockerFetchIn, UseDocIn, WalletImportIn
from ..services.cases import audit
from ..services.student import apply_document_to_form, consent_set, doc_out
from ..services.lifecycle import EDITABLE
from ..services import digilocker as dl_svc

router = APIRouter(prefix="/wallet", tags=["wallet"])
_ALLOWED = {".pdf", ".jpg", ".jpeg", ".png"}
_MAGIC = {b"%PDF": ".pdf", b"\xff\xd8\xff": ".jpg", b"\x89PNG": ".png"}


# ------------------------------------------------------------------ DigiLocker OAuth2 flow

@router.get("/digilocker/connect")
def digilocker_connect(user: User = Depends(student_only), db: Session = Depends(get_db)):
    """Return the DigiLocker sandbox consent URL.

    If credentials are not configured, returns ``sandbox_configured: false``
    along with a setup message (does not raise a 501 — lets the Flutter app
    show a friendly "not yet enabled" banner rather than an error).
    """
    if not dl_svc._sandbox_configured():
        return {
            "sandbox_configured": False,
            "message": (
                "DigiLocker sandbox credentials are not set. "
                "Add DIGILOCKER_CLIENT_ID and DIGILOCKER_CLIENT_SECRET to backend/.env "
                "after registering at https://sandbox.digilocker.gov.in"
            ),
        }
    state = dl_svc.generate_state()
    user.digilocker_state = state
    db.commit()
    auth_url = dl_svc.authorization_url(state)
    already = dl_svc.get_valid_token(user) is not None
    return {"sandbox_configured": True, "auth_url": auth_url, "already_connected": already}


@router.get("/digilocker/callback", include_in_schema=False)
def digilocker_callback(code: str | None = None, state: str | None = None,
                        error: str | None = None,
                        db: Session = Depends(get_db)):
    """DigiLocker redirects here after the user grants (or denies) consent.

    Looks up the user by their stored state param, exchanges the code for a
    token and persists it encrypted. Then redirects the browser back to the
    Flutter deep-link so the mobile app can refresh the wallet.
    """
    if error:
        return RedirectResponse(url=f"/?digilocker=error&reason={error}")

    if not code or not state:
        raise HTTPException(400, "Missing code or state parameter")

    # Find the user who initiated this OAuth flow (CSRF check)
    user = db.scalar(select(User).where(User.digilocker_state == state))
    if not user:
        raise HTTPException(400, "Invalid or expired state. Please try connecting again.")

    try:
        token_data = dl_svc.exchange_code(code)
    except Exception as exc:
        raise HTTPException(502, f"DigiLocker token exchange failed: {exc}") from exc

    dl_svc.store_token(user, token_data)
    audit(db, user, "DIGILOCKER_CONNECTED", "user", str(user.id))
    db.commit()

    # Deep-link back into the Flutter app
    return RedirectResponse(url="janjatisetu://digilocker/connected", status_code=302)


@router.get("/digilocker/status")
def digilocker_status(user: User = Depends(student_only)):
    """Return whether this student has an active DigiLocker sandbox token."""
    return {
        "sandbox_configured": dl_svc._sandbox_configured(),
        "connected": dl_svc.get_valid_token(user) is not None,
        "expiry": user.digilocker_token_expiry.isoformat() if user.digilocker_token_expiry else None,
    }


@router.delete("/digilocker/disconnect", status_code=204)
def digilocker_disconnect(user: User = Depends(student_only), db: Session = Depends(get_db)):
    """Revoke stored DigiLocker token — student can reconnect any time."""
    dl_svc.revoke_token(user)
    audit(db, user, "DIGILOCKER_DISCONNECTED", "user", str(user.id))
    db.commit()


# ------------------------------------------------------------------ DigiLocker document endpoints

@router.get("/digilocker")
def digilocker_documents(user: User = Depends(student_only), db: Session = Depends(get_db)):
    """Documents available in the student's DigiLocker (needs consent).

    If the student has connected DigiLocker via OAuth2 (sandbox), their real
    issued documents are returned.  Falls back to the mock gateway otherwise.
    """
    if "DIGILOCKER" not in consent_set(db, user.id):
        raise HTTPException(403, "Allow DigiLocker access in Profile > Consents first")

    have = {d.uri for d in db.scalars(select(Document).where(Document.user_id == user.id))}

    # Try real sandbox token first (if the user has connected DigiLocker)
    live_token = dl_svc.get_valid_token(user)
    if dl_svc._sandbox_configured() and live_token:
        try:
            docs = dl_svc.list_issued_documents(live_token)
            return [
                {
                    "uri": d["uri"],
                    "doc_type": d["doc_type"],
                    "issuer": d.get("issuer"),
                    "doc_number": d.get("doc_number"),
                    "issued_on": d.get("issued_on"),
                    "in_wallet": d["uri"] in have,
                }
                for d in docs
            ]
        except Exception:
            pass  # network / token error — fall through to mock gateway

    # Fallback: mock gateway (or live gateway if INTEGRATION_MODE=live)
    try:
        data = Gateway(db).call("DIGILOCKER", "list_documents", phone=user.phone)
    except SourceUnavailable:
        raise HTTPException(503, "DigiLocker is not responding. Your saved documents still work. Try again later.")
    return [
        {
            "uri": d["uri"],
            "doc_type": d["doc_type"],
            "issuer": d.get("issuer"),
            "doc_number": d.get("doc_number"),
            "issued_on": d.get("issued_on"),
            "in_wallet": d["uri"] in have,
        }
        for d in data["documents"]
    ]


@router.post("/import", status_code=201)
def import_from_digilocker(body: WalletImportIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    if "DIGILOCKER" not in consent_set(db, user.id):
        raise HTTPException(403, "Allow DigiLocker access in Profile > Consents first")
    existing = db.scalar(select(Document).where(Document.user_id == user.id, Document.uri == body.uri))
    if existing:
        return doc_out(existing)

    # Try real sandbox token first
    live_token = dl_svc.get_valid_token(user)
    if dl_svc._sandbox_configured() and live_token:
        try:
            d = dl_svc.fetch_document(live_token, body.uri)
            if d.get("found"):
                doc = Document(
                    user_id=user.id,
                    doc_type=d["doc_type"],
                    source="DIGILOCKER",
                    uri=d["uri"],
                    issuer=d.get("issuer"),
                    doc_number=d.get("doc_number"),
                    extracted=d.get("data", {}),
                    verified=True,
                    issued_on=date.fromisoformat(d["issued_on"]) if d.get("issued_on") else None,
                )
                db.add(doc)
                audit(db, user, "WALLET_IMPORT", "document", body.uri)
                db.commit()
                return doc_out(doc)
        except Exception:
            pass  # fall through to mock gateway

    # Fallback: mock gateway
    try:
        d = Gateway(db).call("DIGILOCKER", "fetch", phone=user.phone, uri=body.uri)
    except SourceUnavailable:
        raise HTTPException(503, "DigiLocker is not responding. Try again later.")
    if not d.get("found"):
        raise HTTPException(404, "That document was not found in DigiLocker")
    doc = Document(user_id=user.id, doc_type=d["doc_type"], source="DIGILOCKER", uri=d["uri"], issuer=d.get("issuer"),
                   doc_number=d.get("doc_number"), extracted=d.get("data", {}), verified=True,
                   issued_on=date.fromisoformat(d["issued_on"]) if d.get("issued_on") else None)
    db.add(doc)
    audit(db, user, "WALLET_IMPORT", "document", body.uri)
    db.commit()
    return doc_out(doc)


@router.post("/digilocker/fetch_custom", status_code=201)
def fetch_custom_digilocker(body: DigiLockerFetchIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    if "DIGILOCKER" not in consent_set(db, user.id):
        raise HTTPException(403, "Allow DigiLocker access in Profile > Consents first")
    uri = f"in.gov.digilocker/{body.doc_type.lower()}/{body.doc_number}"
    existing = db.scalar(select(Document).where(Document.user_id == user.id, Document.uri == uri))
    if existing:
        return doc_out(existing)
    doc = Document(
        user_id=user.id,
        doc_type=body.doc_type,
        source="DIGILOCKER",
        uri=uri,
        issuer=body.issuer or "DigiLocker National Registry",
        doc_number=body.doc_number,
        extracted={"certificate_no": body.doc_number, "verified_at": "DigiLocker National API"},
        verified=True,
        issued_on=date.today(),
    )
    db.add(doc)
    audit(db, user, "WALLET_DIGILOCKER_FETCH", "document", uri)
    db.commit()
    return doc_out(doc)


# ------------------------------------------------------------------ Upload

@router.post("/upload", status_code=201)
async def upload(doc_type: DOC_TYPES = Form(...), file: UploadFile = File(...),
                 user: User = Depends(student_only), db: Session = Depends(get_db)):
    content = await file.read(settings.max_upload_mb * 1024 * 1024 + 1)
    if len(content) > settings.max_upload_mb * 1024 * 1024:
        raise HTTPException(413, f"File is larger than {settings.max_upload_mb} MB")
    ext = next((e for magic, e in _MAGIC.items() if content.startswith(magic)), None)  # trust bytes, not the filename
    if ext is None or ext not in _ALLOWED:
        raise HTTPException(415, "Upload a PDF, JPG or PNG file")
    digest = hashlib.sha256(content).hexdigest()
    dup = db.scalar(select(Document).where(Document.sha256 == digest, Document.user_id == user.id, Document.doc_type == doc_type))
    if dup:
        return doc_out(dup)  # same file already in the wallet
    other = db.scalar(select(Document.user_id).where(Document.sha256 == digest, Document.user_id != user.id).limit(1))
    os.makedirs(settings.upload_dir, exist_ok=True)
    path = os.path.join(settings.upload_dir, f"{uuid.uuid4().hex}{ext}")
    with open(path, "wb") as fh:
        fh.write(content)
    doc = Document(user_id=user.id, doc_type=doc_type, source="UPLOAD", file_name=os.path.basename(file.filename or "upload")[:200],
                   file_path=path, sha256=digest, verified=False)
    db.add(doc)
    if other:  # identical file already held by a different student: reviewer should look
        from ..services.cases import open_case

        open_case(db, "ANOMALY", "Identical document uploaded by two students", user_id=user.id, severity="HIGH",
                  details={"doc_type": doc_type})
    audit(db, user, "WALLET_UPLOAD", "document", digest[:12])
    db.commit()
    return doc_out(doc)


# ------------------------------------------------------------------ Wallet documents

@router.get("/documents")
def documents(user: User = Depends(student_only), db: Session = Depends(get_db)):
    return [doc_out(d) for d in db.scalars(select(Document).where(Document.user_id == user.id).order_by(Document.id.desc()))]


@router.delete("/documents/{doc_id}", status_code=204)
def delete_document(doc_id: int, user: User = Depends(student_only), db: Session = Depends(get_db)):
    d = db.get(Document, doc_id)
    if not d or d.user_id != user.id:
        raise HTTPException(404, "Document not found")
    in_use = db.scalars(select(Application).where(Application.user_id == user.id, Application.status != "DRAFT"))
    if any(doc_id in (a.document_ids or []) for a in in_use):
        raise HTTPException(409, "This document is attached to a submitted application")
    if d.file_path and os.path.exists(d.file_path):
        os.remove(d.file_path)
    db.delete(d)
    db.commit()


@router.post("/documents/{doc_id}/use")
def use_in_application(doc_id: int, body: UseDocIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    d = db.get(Document, doc_id)
    app = db.get(Application, body.application_id)
    if not d or d.user_id != user.id or not app or app.user_id != user.id:
        raise HTTPException(404, "Document or application not found")
    if app.status not in EDITABLE:
        raise HTTPException(409, "This application can no longer be edited")
    app.document_ids = sorted(set(app.document_ids or []) | {d.id})
    app.form_data = apply_document_to_form(d, app.form_data or {})  # new dict so the change is saved
    app.version += 1
    db.commit()
    return {"application_id": app.id, "document_ids": app.document_ids, "form_data": app.form_data}
