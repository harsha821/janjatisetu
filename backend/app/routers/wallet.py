import hashlib
import os
import uuid
from datetime import date

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..deps import student_only
from ..integrations.gateway import Gateway, SourceUnavailable
from ..models import Application, Document, User
from ..schemas import DOC_TYPES, UseDocIn, WalletImportIn
from ..services.cases import audit
from ..services.student import apply_document_to_form, consent_set, doc_out
from ..services.lifecycle import EDITABLE

router = APIRouter(prefix="/wallet", tags=["wallet"])
_ALLOWED = {".pdf", ".jpg", ".jpeg", ".png"}
_MAGIC = {b"%PDF": ".pdf", b"\xff\xd8\xff": ".jpg", b"\x89PNG": ".png"}


@router.get("/digilocker")
def digilocker_documents(user: User = Depends(student_only), db: Session = Depends(get_db)):
    """Documents available in the student's DigiLocker (needs consent)."""
    if "DIGILOCKER" not in consent_set(db, user.id):
        raise HTTPException(403, "Allow DigiLocker access in Profile > Consents first")
    try:
        data = Gateway(db).call("DIGILOCKER", "list_documents", phone=user.phone)
    except SourceUnavailable:
        raise HTTPException(503, "DigiLocker is not responding. Your saved documents still work. Try again later.")
    have = {d.uri for d in db.scalars(select(Document).where(Document.user_id == user.id))}
    return [{"uri": d["uri"], "doc_type": d["doc_type"], "issuer": d.get("issuer"), "doc_number": d.get("doc_number"),
             "issued_on": d.get("issued_on"), "in_wallet": d["uri"] in have} for d in data["documents"]]


@router.post("/import", status_code=201)
def import_from_digilocker(body: WalletImportIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    if "DIGILOCKER" not in consent_set(db, user.id):
        raise HTTPException(403, "Allow DigiLocker access in Profile > Consents first")
    existing = db.scalar(select(Document).where(Document.user_id == user.id, Document.uri == body.uri))
    if existing:
        return doc_out(existing)
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
