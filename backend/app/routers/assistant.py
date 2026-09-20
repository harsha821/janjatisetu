from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import student_only
from ..models import Application, Document, Scheme, User
from ..schemas import ChatIn
from ..services import assistant
from ..services.student import eligibility_for, get_profile

router = APIRouter(tags=["assistant"])


def _build_context(db: Session, user: User) -> dict:
    profile = get_profile(db, user)
    elig = eligibility_for(db, profile)
    schemes = {s.code: s for s in db.scalars(select(Scheme))}
    apps = list(db.scalars(select(Application).where(Application.user_id == user.id).order_by(Application.updated_at.desc())))
    docs_have = [d.doc_type for d in db.scalars(select(Document).where(Document.user_id == user.id))]
    documents_by_scheme = {s.code: s.documents for s in schemes.values()}
    applications = [{
        "scheme_name": schemes[a.scheme_code].short_name if a.scheme_code in schemes else a.scheme_code,
        "status": a.status,
        "open_deficiencies": [d.message for d in a.deficiencies if not d.resolved],
        "sanctioned": a.sanctioned_amount, "paid": a.paid_amount,
    } for a in apps]
    return {"name": user.full_name.split(" ")[0] if user.full_name else "", "eligibility": elig,
           "documents_have": docs_have, "documents_by_scheme": documents_by_scheme, "applications": applications}


@router.post("/assistant/chat")
def chat(body: ChatIn, user: User = Depends(student_only), db: Session = Depends(get_db)):
    ctx = _build_context(db, user)
    return assistant.reply(body.message, user.language or "en", ctx)
