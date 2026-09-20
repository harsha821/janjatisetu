from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import StudentProfile, User
from ..schemas import RegisterIn
from ..security import create_access_token, hash_password, verify_password
from ..services.cases import audit

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_response(user: User) -> dict:
    return {"access_token": create_access_token(user.id, user.role), "token_type": "bearer",
            "role": user.role, "user_id": user.id, "full_name": user.full_name, "language": user.language}


@router.post("/register", status_code=201)
def register(body: RegisterIn, db: Session = Depends(get_db)):
    if db.scalar(select(User).where(User.phone == body.phone)):
        raise HTTPException(409, "An account with this phone number already exists")
    user = User(phone=body.phone, email=body.email, full_name=body.full_name, role="STUDENT",
               language=body.language, password_hash=hash_password(body.password))
    db.add(user)
    db.flush()
    db.add(StudentProfile(user_id=user.id))
    audit(db, user, "REGISTER", "user", user.id)
    db.commit()
    return _token_response(user)


@router.post("/login")
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    """OAuth2 password flow: `username` carries the phone number."""
    user = db.scalar(select(User).where(User.phone == form.username))
    if not user or not user.is_active or not verify_password(form.password, user.password_hash):
        raise HTTPException(401, "Incorrect phone number or password")
    audit(db, user, "LOGIN", "user", user.id)
    db.commit()
    return _token_response(user)


@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return {"user_id": user.id, "phone": user.phone, "email": user.email, "full_name": user.full_name,
            "role": user.role, "language": user.language}
