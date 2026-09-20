"""Integration gateway: the only path from JanjatiSetu to external systems.

Sources: DIGILOCKER, UIDAI, APAAR, UDISE, AISHE, EDISTRICT, UGC_NTA (data)
         NSP, SFMP, NOS (scholarship portals)

  mock mode  answers from the local database (ExternalRegistry, ScholarshipRecord)
  live mode  POSTs to LIVE_ENDPOINTS[source]/{op} with an OAuth 2.0
             client-credentials token over mutual TLS

The live request/response contracts below are PLACEHOLDERS. Real contracts,
credentials and data-sharing agreements come from each owning department
(NIC, UIDAI, UGC-NTA, DigiLocker, NSP etc.) and must be substituted here.
Any failure surfaces as SourceUnavailable so callers can route it to
exception management instead of failing the student's request.
"""
import time
import uuid
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..models import ExternalRegistry, ScholarshipRecord

SOURCES = {"DIGILOCKER", "UIDAI", "APAAR", "UDISE", "AISHE", "EDISTRICT", "UGC_NTA", "NSP", "SFMP", "NOS"}
PORTAL_KEY = {"NSP/OTR": "NSP", "SFMP": "SFMP", "NOS": "NOS"}


class SourceUnavailable(Exception):
    def __init__(self, source: str, reason: str = "temporarily unavailable"):
        self.source = source
        super().__init__(f"{source} {reason}")


class Gateway:
    def __init__(self, db: Session):
        self.db = db
        self._token: tuple[str, float] | None = None

    # ------------------------------------------------------------------ public
    def call(self, source: str, op: str, **params) -> dict:
        source = source.upper()
        if source not in SOURCES:
            raise ValueError(f"unknown source {source}")
        if source in settings.outage_set:
            raise SourceUnavailable(source, "is not responding (simulated outage)")
        if settings.integration_mode == "live":
            return self._live(source, op, params)
        return self._mock(source, op, params)

    # -------------------------------------------------------------------- mock
    def _registry(self, source: str, key: str | None) -> dict | None:
        if not key:
            return None
        row = self.db.scalar(
            select(ExternalRegistry).where(ExternalRegistry.source == source, ExternalRegistry.key == key)
        )
        return row.payload if row else None

    def _mock(self, source: str, op: str, p: dict) -> dict:
        if source == "DIGILOCKER":
            data = self._registry("DIGILOCKER", p.get("phone")) or {"documents": []}
            if op == "list_documents":
                return data
            if op == "fetch":
                for d in data["documents"]:
                    if d["uri"] == p.get("uri"):
                        return {"found": True, **d}
                return {"found": False}
        if source == "UIDAI" and op == "verify_identity":
            rec = self._registry("UIDAI", p.get("aadhaar_hash"))
            return {"found": bool(rec), **(rec or {})}
        if source == "APAAR" and op == "lookup":
            rec = self._registry("APAAR", p.get("apaar_id"))
            return {"found": bool(rec), **(rec or {})}
        if source in ("UDISE", "AISHE") and op == "institution":
            rec = self._registry(source, p.get("institution_code"))
            return {"found": bool(rec), **(rec or {})}
        if source == "EDISTRICT" and op == "certificates":
            rec = self._registry("EDISTRICT", p.get("aadhaar_hash"))
            return {"found": bool(rec), **(rec or {})}
        if source == "UGC_NTA" and op == "qualification":
            rec = self._registry("UGC_NTA", p.get("roll"))
            return {"found": bool(rec), **(rec or {})}
        if source in ("NSP", "SFMP", "NOS"):
            return self._mock_portal(source, op, p)
        raise ValueError(f"unsupported operation {source}.{op}")

    def _mock_portal(self, source: str, op: str, p: dict) -> dict:
        if op == "submit":
            ref = f"{source}-{datetime.now().year}-{uuid.uuid4().hex[:8].upper()}"
            f = p["form"]
            self.db.add(ScholarshipRecord(
                portal={"NSP": "NSP/OTR"}.get(source, source),
                scheme_code=p["scheme_code"], apaar_id=f.get("apaar_id"), name=f.get("applicant_name") or "",
                dob=date.fromisoformat(f["dob"]) if f.get("dob") else None, gender=f.get("gender"), state=f.get("state"), district=f.get("district"),
                institution_name=f.get("institution_name"), academic_year=p.get("academic_year", "2026-27"),
                status="SUBMITTED", external_ref=ref,
            ))
            self.db.flush()
            return {"external_ref": ref, "status": "SUBMITTED"}
        if op == "status":
            rec = self.db.scalar(select(ScholarshipRecord).where(ScholarshipRecord.external_ref == p.get("external_ref")))
            return {"found": bool(rec), "status": rec.status if rec else None}
        raise ValueError(f"unsupported operation {source}.{op}")

    # -------------------------------------------------------------------- live
    def _access_token(self) -> str:
        import httpx

        if self._token and self._token[1] > time.time() + 30:
            return self._token[0]
        r = httpx.post(
            settings.gateway_token_url,
            data={"grant_type": "client_credentials", "client_id": settings.gateway_client_id,
                  "client_secret": settings.gateway_client_secret},
            cert=(settings.mtls_cert, settings.mtls_key) if settings.mtls_cert else None,
            verify=settings.mtls_ca or True, timeout=8,
        )
        r.raise_for_status()
        body = r.json()
        self._token = (body["access_token"], time.time() + int(body.get("expires_in", 300)))
        return self._token[0]

    def _live(self, source: str, op: str, params: dict) -> dict:
        import httpx

        base = settings.live_endpoints.get(source)
        if not base:
            raise SourceUnavailable(source, "has no live endpoint configured")
        last: Exception | None = None
        for attempt in range(3):
            try:
                r = httpx.post(
                    f"{base.rstrip('/')}/{op}", json=params,
                    headers={"Authorization": f"Bearer {self._access_token()}"},
                    cert=(settings.mtls_cert, settings.mtls_key) if settings.mtls_cert else None,
                    verify=settings.mtls_ca or True, timeout=8,
                )
                if r.status_code >= 500:
                    raise httpx.HTTPError(f"HTTP {r.status_code}")
                r.raise_for_status()
                return r.json()
            except Exception as exc:  # network, TLS, 5xx, auth
                last = exc
                time.sleep(0.25 * 2 ** attempt)
        raise SourceUnavailable(source, f"failed after retries ({type(last).__name__})")
