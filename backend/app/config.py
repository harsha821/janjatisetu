"""Application settings, read from environment variables / .env (see .env.example)."""
import json
from functools import cached_property

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "JanjatiSetu"

    # --- security -----------------------------------------------------------
    secret_key: str = "change-me-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days: rural/offline-first, long-lived tokens
    field_encryption_key: str = ""  # Fernet key for bank account numbers; auto-generated if empty (dev only)

    # --- database -------------------------------------------------------------
    database_url: str = "sqlite:///./janjatisetu.db"

    # --- CORS -----------------------------------------------------------------
    cors_origins: str = "*"

    @cached_property
    def cors_list(self) -> list[str]:
        if self.cors_origins == "*":
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    # --- seed / demo ------------------------------------------------------------
    seed_demo: bool = True

    # --- uploads --------------------------------------------------------------
    upload_dir: str = "./uploads"
    max_upload_mb: int = 10

    # --- integration gateway ---------------------------------------------------
    integration_mode: str = "mock"  # mock | live
    simulate_outages: str = ""  # comma-separated source names, e.g. "UIDAI,NSP"
    gateway_token_url: str = ""
    gateway_client_id: str = ""
    gateway_client_secret: str = ""
    mtls_cert: str = ""
    mtls_key: str = ""
    mtls_ca: str = ""
    live_endpoints_json: str = "{}"  # JSON object: {"UIDAI": "https://...", ...}

    # --- DigiLocker sandbox OAuth2 --------------------------------------------
    digilocker_client_id: str = ""
    digilocker_client_secret: str = ""
    digilocker_redirect_uri: str = "http://localhost:8000/api/v1/wallet/digilocker/callback"
    digilocker_sandbox: bool = True  # True → sandbox.digilocker.gov.in, False → api.digilocker.gov.in

    @property
    def digilocker_base_url(self) -> str:
        return "https://sandbox.digilocker.gov.in" if self.digilocker_sandbox else "https://api.digilocker.gov.in"

    @property
    def outage_set(self) -> set[str]:
        return {s.strip().upper() for s in self.simulate_outages.split(",") if s.strip()}

    @property
    def live_endpoints(self) -> dict[str, str]:
        try:
            return json.loads(self.live_endpoints_json)
        except (ValueError, TypeError):
            return {}

    # --- notifications ----------------------------------------------------------
    fcm_enabled: bool = False
    fcm_credentials_file: str = ""
    sms_enabled: bool = False
    sms_provider_api_key: str = ""
    sms_sender_id: str = "JNJSTU"


settings = Settings()
