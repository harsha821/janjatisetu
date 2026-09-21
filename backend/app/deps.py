from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jwt import PyJWTError
from sqlalchemy.orm import Session

from .database import get_db
from .models import User
from .security import decode_access_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=False)

_CREDENTIALS_ERROR = HTTPException(status.HTTP_401_UNAUTHORIZED, "Could not validate credentials",
                                   headers={"WWW-Authenticate": "Bearer"})


def get_current_user(request: Request, token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    if not token:
        token = request.query_params.get("token")
    if not token:
        raise _CREDENTIALS_ERROR
    try:
        payload = decode_access_token(token)
        user_id = int(payload.get("sub"))
    except (PyJWTError, TypeError, ValueError):
        raise _CREDENTIALS_ERROR
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise _CREDENTIALS_ERROR
    return user


def student_only(user: User = Depends(get_current_user)) -> User:
    if user.role != "STUDENT":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Students only")
    return user


def staff_only(user: User = Depends(get_current_user)) -> User:
    if user.role not in ("VERIFIER", "ADMIN"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ministry staff only")
    return user


def admin_only(user: User = Depends(get_current_user)) -> User:
    if user.role != "ADMIN":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Ministry admin only")
    return user
