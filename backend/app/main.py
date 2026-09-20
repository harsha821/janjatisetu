import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, RedirectResponse

from .config import settings
from .database import SessionLocal, init_db
from .routers import admin, applications, assistant, auth, notifications, profile, sync, wallet
from .services.workflow import WorkflowError

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("janjatisetu")


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    if settings.secret_key == "change-me-in-production":
        log.warning("SECRET_KEY is the default value. Set a strong secret before deploying.")
    with SessionLocal() as db:
        from .seed import seed_schemes

        seed_schemes(db)  # scheme rules are needed in every environment
        if settings.seed_demo:
            from .seed import seed_demo

            seed_demo(db)
    yield


app = FastAPI(title=settings.app_name, version="1.0.0", lifespan=lifespan,
              description="Unified scholarship platform for ST/PVTG students (SIH26238).")

app.add_middleware(CORSMiddleware, allow_origins=settings.cors_list, allow_credentials=False,
                   allow_methods=["*"], allow_headers=["*"])


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.exception_handler(WorkflowError)
async def workflow_error(_: Request, exc: WorkflowError):
    return JSONResponse(status_code=409, content={"detail": str(exc)})


API = "/api/v1"
for r in (auth.router, profile.router, wallet.router, applications.router, sync.router, notifications.router,
         admin.router, assistant.router):
    app.include_router(r, prefix=API)


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/docs")


@app.get("/api/v1", include_in_schema=False)
def api_root():
    return RedirectResponse(url="/docs")


@app.get("/health", tags=["meta"])
def health():
    return {"status": "ok", "integration_mode": settings.integration_mode}
