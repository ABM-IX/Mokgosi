"""Mokgosi incident API. The trusted-person and response-network routes fail independently."""

import hashlib
import hmac
import logging
import os
import secrets
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any, Literal, Optional
from uuid import UUID, uuid4

from dotenv import load_dotenv

load_dotenv()

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, Response
from pydantic import BaseModel, Field, field_validator
from supabase import Client, create_client

from services.acoustic_worker import analyze
from services.analytics_service import aggregate_hotspots
from services.evidence_service import (
    _bundle_cache,
    generate_bundle_token,
    generate_case_bundle_zip,
    verify_bundle_token,
    verify_bundle_zip,
)
from services.evidence_vault import (
    build_keyring,
    key_id_for,
    load_private_key,
    public_key_hex,
    sign_manifest,
    verify_with_keyring,
)
from services.priority_engine import assign_initial_priority
from services.safe_network import (
    format_neutral_sms,
    generate_ack_token,
    run_escalation_chain,
    verify_ack_token,
)
from services.trusted_notifier import dispatch, validate_e164

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("mokgosi.api")

# Refuse to run with ephemeral/rotating signing keys. This key remains process stable.
# Retired public keys (ED25519_PUBLIC_KEYRING) keep pre-rotation evidence verifiable.
try:
    PRIVATE_KEY = load_private_key()
    PUBLIC_KEY_HEX = public_key_hex(PRIVATE_KEY)
    KEYRING = build_keyring(PUBLIC_KEY_HEX, os.getenv("ED25519_PUBLIC_KEYRING"))
except ValueError as exc:
    raise RuntimeError(str(exc)) from exc
KEY_ID = key_id_for(PUBLIC_KEY_HEX)

app = FastAPI(title="MOKGOSI Incident & Evidence Engine", version="2.1")
cors_origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173").split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Device-Key", "X-Device-Token"],
)

_rate_lock = threading.Lock()
_rate_windows: dict[str, list[float]] = {}
# Per registered device / responder. Unregistered callers only get the per-IP bucket, and nobody
# shares a bucket with every other install (the APK key is the same on every phone).
RATE_LIMIT = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))
RATE_LIMIT_PER_IP = int(os.getenv("RATE_LIMIT_PER_IP_PER_MINUTE", "120"))
REGISTRATIONS_PER_IP_PER_HOUR = int(os.getenv("REGISTRATIONS_PER_IP_PER_HOUR", "20"))
OPEN_STATUSES = ["CREATED", "ACKNOWLEDGED", "ASSIGNED", "DISPATCHED"]
PRIORITY_RANK = {"P3_VERIFY": 1, "P2_HIGH": 2, "P1_CRITICAL": 3}
NEXT_STATUS = {"CREATED": "ACKNOWLEDGED", "ACKNOWLEDGED": "ASSIGNED", "ASSIGNED": "DISPATCHED", "DISPATCHED": "RESOLVED"}


@lru_cache(maxsize=1)
def get_db() -> Client:
    """Create one Supabase client per process after validating required config."""
    url, key = os.getenv("SUPABASE_URL", ""), os.getenv("SUPABASE_KEY", "")
    if not url.startswith("https://") or not key or "YOUR_" in key:
        raise RuntimeError("Supabase is not configured. Set SUPABASE_URL and SUPABASE_KEY.")
    return create_client(url, key)


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _consume(key: str, limit: int, window_seconds: float = 60) -> None:
    """In-memory sliding window; per process, so limits reset on restart."""
    now = time.monotonic()
    with _rate_lock:
        recent = [stamp for stamp in _rate_windows.get(key, []) if now - stamp < window_seconds]
        if len(recent) >= limit:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        recent.append(now)
        _rate_windows[key] = recent


def _rate_limit(request: Request, identity: str) -> None:
    ip_key = f"ip:{_client_ip(request)}"
    _consume(ip_key, RATE_LIMIT_PER_IP)
    if identity != ip_key:
        _consume(identity, RATE_LIMIT)


@dataclass(frozen=True)
class DeviceContext:
    """Who is calling. `user_id` is only set when a registered per-device token was presented."""

    rate_identity: str
    device_id: str | None = None
    user_id: str | None = None
    lookup_failed: bool = False

    @property
    def registered(self) -> bool:
        return self.user_id is not None


def _hash_device_token(token: str) -> str:
    # Tokens are 256-bit random values, so a fast hash is enough; only the hash is stored.
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _check_app_key(x_device_key: Optional[str]) -> None:
    """X-Device-Key ships inside every APK, so it only says "probably our app", never who is calling."""
    configured = [value.strip() for value in os.getenv("DEVICE_API_KEYS", os.getenv("DEVICE_API_KEY", "")).split(",") if value.strip()]
    if not x_device_key or not configured or not any(hmac.compare_digest(x_device_key, value) for value in configured):
        raise HTTPException(status_code=401, detail="Valid X-Device-Key required")


def require_device(
    request: Request,
    x_device_key: Optional[str] = Header(default=None),
    x_device_token: Optional[str] = Header(default=None),
) -> DeviceContext:
    """App gate plus optional per-device identity. Token problems never block a caller here, so an
    SOS still goes through; routes that touch private data use require_registered_device instead."""
    _check_app_key(x_device_key)
    device: DeviceContext | None = None
    lookup_failed = False
    if x_device_token:
        try:
            rows = _result_data(
                get_db().table("devices").select("id,user_id,active")
                .eq("device_key_hash", _hash_device_token(x_device_token)).limit(1)
            )
            if rows and rows[0].get("active", True):
                device = DeviceContext(f"device:{rows[0]['id']}", str(rows[0]["id"]), str(rows[0]["user_id"]))
        except Exception:
            lookup_failed = True
            logger.warning("Device token lookup unavailable; continuing as an unregistered caller")
    if device is None:
        device = DeviceContext(f"ip:{_client_ip(request)}", lookup_failed=lookup_failed)
    _rate_limit(request, device.rate_identity)
    return device


def require_registered_device(device: DeviceContext = Depends(require_device)) -> DeviceContext:
    if device.lookup_failed:
        raise HTTPException(status_code=503, detail="Device verification unavailable")
    if not device.registered:
        raise HTTPException(status_code=401, detail="Registered device token required (X-Device-Token)")
    return device


def _require_owner(device: DeviceContext, claimed_user_id: str | None) -> str:
    """Survivor data is keyed by the token's user; a different user_id in the request is refused."""
    if claimed_user_id and claimed_user_id != device.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: this device cannot access another survivor's data")
    return str(device.user_id)


def _user_id_from_response(response: Any) -> str | None:
    user = getattr(response, "user", None)
    if user is None and isinstance(response, dict):
        user = response.get("user")
    user_id = getattr(user, "id", None) if user is not None else None
    if user_id is None and isinstance(user, dict):
        user_id = user.get("id")
    return str(user_id) if user_id else None


def _is_responder(response: Any) -> bool:
    user = getattr(response, "user", None)
    if user is None and isinstance(response, dict):
        user = response.get("user")
    metadata = getattr(user, "app_metadata", None) if user is not None else None
    if metadata is None and isinstance(user, dict):
        metadata = user.get("app_metadata")
    metadata = metadata if isinstance(metadata, dict) else {}
    roles = metadata.get("roles", [])
    return metadata.get("role") == "responder" or (isinstance(roles, list) and "responder" in roles)


def require_responder(request: Request, authorization: Optional[str] = Header(default=None)) -> str:
    """Verify the bearer token through Supabase Auth; identity comes from its user object."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Supabase responder bearer token required")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Invalid responder token")
    demo_token = os.getenv("DEMO_RESPONDER_TOKEN", "").strip()
    if os.getenv("DEMO_MODE", "false").lower() == "true" and demo_token and hmac.compare_digest(token, demo_token):
        responder_id = os.getenv("DEMO_RESPONDER_ID", "DEMO_RESPONDER_01").strip() or "DEMO_RESPONDER_01"
        _rate_limit(request, f"responder:{responder_id}")
        return responder_id
    try:
        user = get_db().auth.get_user(token)
        user_id = _user_id_from_response(user)
    except Exception as exc:
        logger.info("Responder authentication rejected: %s", exc)
        raise HTTPException(status_code=401, detail="Invalid responder token") from exc
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid responder token")
    if not _is_responder(user):
        raise HTTPException(status_code=403, detail="Verified Supabase user is not a responder")
    _rate_limit(request, f"responder:{user_id}")
    return user_id


def require_device_or_responder(
    request: Request,
    x_device_key: Optional[str] = Header(default=None),
    x_device_token: Optional[str] = Header(default=None),
    authorization: Optional[str] = Header(default=None),
) -> str:
    """Allow either an authenticated responder or a configured device key (for Route 3 audio uploads)."""
    if authorization and authorization.lower().startswith("bearer "):
        return require_responder(request, authorization)
    if x_device_key:
        return require_device(request, x_device_key, x_device_token).rate_identity
    raise HTTPException(status_code=401, detail="Valid X-Device-Key or responder Bearer token required")


class IncidentTriggerPayload(BaseModel):
    user_id: str = Field(min_length=1, max_length=120)
    trusted_contact_phone: Optional[str] = None
    trigger_type: Literal["EXPLICIT_SOS", "DURESS_PIN", "MISSED_CHECKIN", "MOTION_IMPACT", "COVERT_SOS", "SHAKE_SOS"]
    category: Literal["PERSONAL_SAFETY", "GBV_DOMESTIC", "GBV_SEXUAL_VIOLENCE", "GBV_OTHER"] = "PERSONAL_SAFETY"
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    impact_g_force: float = Field(default=1.0, ge=0, le=100)
    source_timestamp_utc: Optional[str] = None
    client_event_id: Optional[UUID] = None

    @field_validator("trusted_contact_phone")
    @classmethod
    def phone_is_e164(cls, value: Optional[str]) -> Optional[str]:
        return validate_e164(value) if value else None


class TrustedContactCreatePayload(BaseModel):
    user_id: Optional[str] = Field(default=None, max_length=120)  # optional: the device token decides
    name: str = Field(min_length=1, max_length=120)
    phone_e164: str
    role: Literal["TRUSTED_PERSON", "FAMILY", "NEIGHBOUR", "SUPPORT_ORG"] = "TRUSTED_PERSON"
    priority: int = Field(default=1, ge=1, le=5)
    notify_on: list[str] = Field(default_factory=lambda: [
        "P1_CRITICAL", "P2_HIGH", "P3_VERIFY", "EXPLICIT_SOS", "DURESS_PIN", "COVERT_SOS", "SHAKE_SOS"
    ])

    @field_validator("phone_e164")
    @classmethod
    def phone_is_e164(cls, value: str) -> str:
        return validate_e164(value)


class TrustedContactUpdatePayload(BaseModel):
    name: Optional[str] = None
    phone_e164: Optional[str] = None
    role: Optional[Literal["TRUSTED_PERSON", "FAMILY", "NEIGHBOUR", "SUPPORT_ORG"]] = None
    priority: Optional[int] = Field(default=None, ge=1, le=5)
    notify_on: Optional[list[str]] = None
    is_active: Optional[bool] = None

    @field_validator("phone_e164")
    @classmethod
    def phone_is_e164(cls, value: Optional[str]) -> Optional[str]:
        return validate_e164(value) if value is not None else None


class EvidenceSharePayload(BaseModel):
    user_id: Optional[str] = Field(default=None, max_length=120)
    entry_ids: list[str] = Field(min_length=1)
    recipient_type: Literal["POLICE", "LEGAL_AID", "COUNSELLOR", "OTHER"]
    notes: Optional[str] = None


class ReferralCreatePayload(BaseModel):
    partner_id: str = Field(min_length=1)
    notes: Optional[str] = None


class ConsentsUpdatePayload(BaseModel):
    user_id: Optional[str] = Field(default=None, max_length=120)
    location: Optional[bool] = True
    audio: Optional[bool] = False
    responder_contact: Optional[bool] = False
    share_evidence: Optional[bool] = False


class LifecycleUpdatePayload(BaseModel):
    new_status: Literal["ACKNOWLEDGED", "ASSIGNED", "DISPATCHED", "RESOLVED"]


class LocationPayload(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    captured_at_utc: Optional[str] = None


class CctvSnapshotPayload(BaseModel):
    camera_id: str = Field(min_length=1, max_length=120)


def _result_data(query: Any) -> list[dict[str, Any]]:
    response = query.execute()
    return getattr(response, "data", None) or []


def _audit(client: Client, incident_id: str | None, actor_id: str, action: str, metadata: dict[str, Any] | None = None) -> bool:
    """Best-effort audit insertion; audit outages must never block an SOS."""
    try:
        client.table("evidence_audit_logs").insert({
            "incident_id": incident_id,
            "actor_id": actor_id,
            "action": action,
            "client_metadata": metadata or {},
        }).execute()
        return True
    except Exception:
        logger.exception("Best-effort audit insert failed: %s", action)
        return False


def _notify_trusted_person(
    incident_id: str,
    payload: IncidentTriggerPayload,
    priority: str,
    client: Client | None,
    verified_identity: bool = False,
) -> None:
    """Run notifier without depending on the response database path. Prioritizes safe network escalation chain.

    Only a registered device token unlocks the server-stored safe network, so a caller who merely
    knows someone's user_id cannot make the server text that person's contacts."""
    if client and verified_identity:
        try:
            base_url = os.getenv("API_BASE_URL", "http://localhost:8000")
            chain_results = run_escalation_chain(
                incident_id,
                payload.user_id,
                payload.category,
                priority,
                payload.lat,
                payload.lng,
                client=client,
                base_url=base_url,
            )
            if chain_results:
                return
        except Exception:
            logger.exception("Safe network escalation failed; falling back to direct contact phone")

    if not payload.trusted_contact_phone:
        logger.warning("Trusted-person dispatch skipped: no verified contact is configured")
        if client:
            _audit(client, incident_id, "MOKGOSI_TRUSTED_NOTIFIER", "TRUSTED_CONTACT_NOT_CONFIGURED", {})
        return
    try:
        outcome = dispatch(incident_id, payload.user_id, payload.trusted_contact_phone, payload.trigger_type,
                           priority, payload.lat, payload.lng)
        success = bool(outcome.get("success"))
        logger.info("Trusted-person dispatch outcome: provider=%s success=%s", outcome.get("provider"), success)
        if client:
            action = ("TRUSTED_CONTACT_DEMO_LOGGED" if outcome.get("provider") == "console" and success
                      else "TRUSTED_CONTACT_ALERTED" if success else "TRUSTED_CONTACT_FAILED")
            _audit(client, incident_id, "MOKGOSI_TRUSTED_NOTIFIER", action,
                   {"provider": outcome.get("provider"), "attempts": outcome.get("attempts"),
                    "demo_only": outcome.get("provider") == "console", "error": outcome.get("error")})
    except Exception as exc:
        logger.exception("Trusted-person dispatch raised an exception")
        if client:
            _audit(client, incident_id, "MOKGOSI_TRUSTED_NOTIFIER", "TRUSTED_CONTACT_FAILED", {"error": str(exc)})


def _queue_notify(background_tasks: BackgroundTasks, incident_id: str, payload: IncidentTriggerPayload,
                  priority: str, client: Client | None, verified_identity: bool = False) -> None:
    background_tasks.add_task(_notify_trusted_person, incident_id, payload, priority, client, verified_identity)


def _lookup_existing(client: Client, client_event_id: UUID | None) -> dict[str, Any] | None:
    if client_event_id is None:
        return None
    rows = _result_data(client.table("incidents").select("*").eq("client_event_id", str(client_event_id)).limit(1))
    return rows[0] if rows else None


def _coalesce_recent(client: Client, payload: IncidentTriggerPayload) -> dict[str, Any] | None:
    cutoff = (datetime.now(timezone.utc) - timedelta(seconds=60)).isoformat()
    rows = _result_data(
        client.table("incidents").select("*").eq("user_id", payload.user_id)
        .gte("created_at", cutoff).in_("status", OPEN_STATUSES).order("created_at", desc=True).limit(1)
    )
    return rows[0] if rows else None


def _safe_incident_id(payload: IncidentTriggerPayload) -> str:
    return str(payload.client_event_id) if payload.client_event_id else "unpersisted-alert"


def _notification_mode() -> str:
    provider = os.getenv("NOTIFIER_PROVIDER", "console").lower()
    return "DEMO_ONLY" if provider == "console" else provider.upper()


def _nearby_cameras(client: Client, payload: IncidentTriggerPayload) -> list[dict[str, Any]]:
    try:
        return _result_data(client.rpc("get_authorized_nearby_cameras", {
            "inc_lat": payload.lat, "inc_lng": payload.lng, "radius_m": 150.0,
        }))
    except Exception:
        logger.exception("Authorized camera lookup unavailable")
        return []


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "MOKGOSI Incident & Evidence Engine",
        "version": "2.1",
        "status": "online",
        "docs": "/docs",
        "health": "/health",
    }


@app.get("/health")
def health() -> dict[str, Any]:
    db_reachable = False
    try:
        client = get_db()
        _result_data(client.table("incidents").select("id").limit(1))
        db_reachable = True
    except Exception:
        db_reachable = False
    return {
        "status": "ok",
        "database_configured": bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_KEY")),
        "database_reachable": db_reachable,
        "demo_mode": os.getenv("DEMO_MODE", "false").lower() == "true",
        "signing_key_id": KEY_ID,
    }


@app.get("/api/v1/evidence/public-key")
def evidence_public_key() -> dict[str, Any]:
    return {
        "public_key_id": KEY_ID,
        "public_key": PUBLIC_KEY_HEX,
        "algorithm": "Ed25519",
        "keyring": [{"public_key_id": key_id, **entry} for key_id, entry in sorted(KEYRING.items())],
    }


@app.post("/api/v1/evidence/verify")
def evidence_verify(manifest: dict[str, Any]) -> dict[str, Any]:
    return verify_with_keyring(manifest, KEYRING)


@app.post("/api/v1/incidents/trigger")
async def trigger_incident(
    payload: IncidentTriggerPayload,
    background_tasks: BackgroundTasks,
    request: Request,
    device: DeviceContext = Depends(require_device),
) -> dict[str, Any]:
    # A registered token decides who this is; without one the body's user_id is only a label.
    if device.registered:
        payload = payload.model_copy(update={"user_id": device.user_id})
    else:
        payload = payload.model_copy(update={"user_id": f"unverified:{payload.user_id.removeprefix('unverified:')}"})
    verified = device.registered
    priority = assign_initial_priority(payload.trigger_type, payload.impact_g_force)
    client: Client | None = None
    try:
        client = get_db()
    except Exception as exc:
        # A missing DB cannot prevent the trusted-person dispatch attempt.
        logger.error("Incident persistence unavailable: %s", exc)
        _queue_notify(background_tasks, _safe_incident_id(payload), payload, priority, None)
        return JSONResponse(status_code=202, content={"status": "ACCEPTED", "incident_persisted": False,
                "persistence_state": "UNAVAILABLE", "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED", "incident": None,
                "notification_mode": _notification_mode(), "authorized_cameras": []})

    existing: dict[str, Any] | None = None
    try:
        existing = _lookup_existing(client, payload.client_event_id)
    except Exception:
        logger.exception("Idempotency lookup failed; attempting incident insert")
    if existing:
        return {"status": "MOKGOSI_ALERT_ACTIVE", "incident_persisted": True, "persistence_state": "PERSISTED",
                "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED", "incident": existing,
                "notification_mode": _notification_mode(), "authorized_cameras": _nearby_cameras(client, payload)}

    try:
        repeated = _coalesce_recent(client, payload)
    except Exception:
        logger.exception("Repeat coalescing query failed; attempting new incident insert")
        repeated = None
    if repeated:
        incident_id = repeated["id"]
        old_priority = repeated.get("priority", "P3_VERIFY")
        raised_priority = priority if PRIORITY_RANK[priority] > PRIORITY_RANK.get(old_priority, 0) else old_priority
        if raised_priority != old_priority:
            try:
                changed = _result_data(client.table("incidents").update({"priority": raised_priority}).eq("id", incident_id))
                if changed:
                    repeated = changed[0]
            except Exception:
                logger.exception("Repeat-trigger priority upgrade failed; existing incident remains active")
            _queue_notify(background_tasks, incident_id, payload, raised_priority, client, verified)
        _audit(client, incident_id, "MOKGOSI_INGEST_ENGINE", "REPEAT_TRIGGER",
               {"trigger_type": payload.trigger_type, "client_event_id": str(payload.client_event_id) if payload.client_event_id else None,
                "priority_before": old_priority, "priority_after": raised_priority})
        return {"status": "MOKGOSI_ALERT_ACTIVE", "incident_persisted": True, "persistence_state": "PERSISTED",
                "notification_state": "ALREADY_QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED", "incident": repeated,
                "notification_mode": _notification_mode(), "authorized_cameras": _nearby_cameras(client, payload)}

    source_ts = payload.source_timestamp_utc or datetime.now(timezone.utc).isoformat()
    row = {
        "user_id": payload.user_id,
        "trusted_contact_phone": payload.trusted_contact_phone,
        "trigger_type": payload.trigger_type,
        "category": payload.category,
        "priority": priority,
        "status": "CREATED",
        "location": f"POINT({payload.lng} {payload.lat})",
        "lat": payload.lat,
        "lng": payload.lng,
        "impact_g_force": payload.impact_g_force,
        "source_capture_utc": source_ts,
        "client_event_id": str(payload.client_event_id) if payload.client_event_id else None,
    }
    try:
        incident_rows = _result_data(client.table("incidents").insert(row))
        if not incident_rows:
            raise RuntimeError("Supabase returned no incident row")
        incident = incident_rows[0]
    except Exception as exc:
        # A concurrent request may have won the unique client_event_id race.
        try:
            existing = _lookup_existing(client, payload.client_event_id)
        except Exception:
            existing = None
        if existing:
            return {"status": "MOKGOSI_ALERT_ACTIVE", "incident_persisted": True, "persistence_state": "PERSISTED",
                    "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED", "incident": existing,
                    "notification_mode": _notification_mode(), "authorized_cameras": _nearby_cameras(client, payload)}
        logger.error("Incident row insert failed; trusted-person path remains queued: %s", exc)
        _queue_notify(background_tasks, _safe_incident_id(payload), payload, priority, None)
        return JSONResponse(status_code=202, content={"status": "ACCEPTED", "incident_persisted": False,
                "persistence_state": "FAILED", "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED", "incident": None,
                "notification_mode": _notification_mode(), "authorized_cameras": []})

    incident_id = incident["id"]
    # Queue route 1 before running optional cameras and audit work for route 2.
    _queue_notify(background_tasks, incident_id, payload, priority, client, verified)
    cameras = _nearby_cameras(client, payload)
    _audit(client, incident_id, "MOKGOSI_INGEST_ENGINE", "INCIDENT_CREATED", {
        "initial_priority": priority, "trigger_type": payload.trigger_type, "matched_cameras": len(cameras),
        "client_ip": request.client.host if request.client else None, "device_verified": verified,
    })
    return {"status": "MOKGOSI_ALERT_ACTIVE", "incident_persisted": True, "persistence_state": "PERSISTED",
            "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED",
            "notification_mode": _notification_mode(), "incident": incident, "authorized_cameras": cameras}


@app.post("/api/v1/incidents/{incident_id}/location")
async def append_location(incident_id: UUID, payload: LocationPayload, _device: DeviceContext = Depends(require_device)):
    try:
        client = get_db()
        incident = _result_data(client.table("incidents").select("id").eq("id", str(incident_id)).limit(1))
        if not incident:
            raise HTTPException(status_code=404, detail="Incident not found")
        row = {"incident_id": str(incident_id), "location": f"POINT({payload.lng} {payload.lat})",
               "lat": payload.lat, "lng": payload.lng,
               "captured_at_utc": payload.captured_at_utc or datetime.now(timezone.utc).isoformat()}
        data = _result_data(client.table("incident_locations").insert(row))
        return {"accepted": bool(data), "location": data[0] if data else None}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Location update could not be persisted")
        raise HTTPException(status_code=503, detail="Location update not persisted") from exc


def _persist_manifest(client: Client, manifest: dict[str, Any]) -> dict[str, Any]:
    """Persist a signed evidence manifest row while keeping the full verification fields for callers."""
    db_row = {k: v for k, v in manifest.items() if k != "public_key"}
    try:
        rows = _result_data(client.table("evidence_manifests").insert(db_row))
        if rows:
            out = dict(rows[0])
            out.setdefault("public_key", manifest.get("public_key"))
            return out
    except Exception:
        logger.exception("Evidence manifest insert failed")
    return manifest


def _store_media_bytes(client: Client, storage_path: str, raw_bytes: bytes, content_type: str) -> str | None:
    """Best-effort upload to Supabase Storage bucket 'evidence-media'; never blocks manifest signing."""
    bucket = os.getenv("EVIDENCE_STORAGE_BUCKET", "evidence-media")
    try:
        storage = getattr(client, "storage", None)
        if storage is None:
            return None
        storage.from_(bucket).upload(storage_path, raw_bytes, {"content-type": content_type})
        return f"{bucket}/{storage_path}"
    except Exception:
        logger.debug("Optional storage upload unavailable for %s", storage_path)
        return None


@app.get("/api/v1/incidents/{incident_id}/track")
async def track_incident_location(incident_id: UUID):
    """Minimal live location summary for Trusted Person tracking links."""
    try:
        client = get_db()
        inc_rows = _result_data(
            client.table("incidents")
            .select("id,priority,status,lat,lng,created_at,source_capture_utc")
            .eq("id", str(incident_id))
            .limit(1)
        )
        if not inc_rows:
            raise HTTPException(status_code=404, detail="Incident not found")
        inc = inc_rows[0]
        loc_rows = _result_data(
            client.table("incident_locations")
            .select("lat,lng,captured_at_utc")
            .eq("incident_id", str(incident_id))
            .order("captured_at_utc", desc=True)
            .limit(1)
        )
        latest = loc_rows[0] if loc_rows else {"lat": inc["lat"], "lng": inc["lng"], "captured_at_utc": inc.get("source_capture_utc") or inc.get("created_at")}
        return {
            "incident_id": str(incident_id),
            "status": inc.get("status"),
            "priority": inc.get("priority"),
            "lat": latest["lat"],
            "lng": latest["lng"],
            "updated_at_utc": latest.get("captured_at_utc"),
            "maps_url": f"https://www.google.com/maps?q={latest['lat']},{latest['lng']}",
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Tracking unavailable") from exc


@app.post("/api/v1/incidents/{incident_id}/acoustic-context")
async def attach_acoustic_context(
    incident_id: UUID,
    simulated_profile: Optional[str] = Form(None),
    source_timestamp_utc: Optional[str] = Form(None),
    audio_file: Optional[UploadFile] = File(None),
    actor_id: str = Depends(require_device_or_responder),
):
    try:
        client = get_db()
        rows = _result_data(client.table("incidents").select("id,priority,source_capture_utc").eq("id", str(incident_id)).limit(1))
        if not rows:
            raise HTTPException(status_code=404, detail="Incident not found")
        source_ts = source_timestamp_utc or rows[0].get("source_capture_utc") or datetime.now(timezone.utc).isoformat()
        raw_bytes: bytes | None = None
        if audio_file is not None:
            raw_bytes = await audio_file.read()
        elif os.getenv("DEMO_MODE", "false").lower() == "true" and simulated_profile:
            raw_bytes = f"mokgosi-demo-audio:{incident_id}:{simulated_profile.upper()}".encode("utf-8")

        signed_manifest: dict[str, Any] | None = None
        if raw_bytes:
            storage_key = f"incidents/{incident_id}/audio-{int(time.time() * 1000)}.wav"
            stored_path = _store_media_bytes(client, storage_key, raw_bytes, "audio/wav") if audio_file is not None else None
            provenance = "MOBILE_FOREGROUND_ESCORT_MIC" if audio_file is not None else "DEMO_ACOUSTIC_SIMULATOR"
            manifest = sign_manifest(
                PRIVATE_KEY,
                str(incident_id),
                raw_bytes,
                "AUDIO_CONTEXT_CLIP",
                provenance,
                source_ts,
                media_storage_path=stored_path,
            )
            signed_manifest = _persist_manifest(client, manifest)

        demo_enabled = os.getenv("DEMO_MODE", "false").lower() == "true"
        if not demo_enabled or not simulated_profile:
            return {
                "ai_context": {
                    "status": "UNAVAILABLE",
                    "model": None,
                    "tags": [],
                    "reason": "Real YAMNet inference is not configured; incident unchanged.",
                },
                "signed_manifest": signed_manifest,
            }
        try:
            profile = analyze(simulated_profile)
        except Exception:
            logger.exception("Demo acoustic worker failed")
            return {
                "ai_context": {
                    "status": "UNAVAILABLE",
                    "model": "DETERMINISTIC_DEMO",
                    "tags": [],
                    "reason": "Acoustic analysis unavailable; incident unchanged.",
                },
                "signed_manifest": signed_manifest,
            }
        current = rows[0].get("priority", "P3_VERIFY")
        target = "P1_CRITICAL" if simulated_profile.upper() == "DISTRESSED" else current
        update: dict[str, Any] = {"ai_context": profile}
        if PRIORITY_RANK.get(target, 0) > PRIORITY_RANK.get(current, 0):
            update["priority"] = target
        data = _result_data(client.table("incidents").update(update).eq("id", str(incident_id)))
        _audit(client, str(incident_id), actor_id, "ACOUSTIC_CONTEXT_ATTACHED", profile)
        return {"ai_context": profile, "incident": data[0] if data else None, "signed_manifest": signed_manifest}
    except HTTPException:
        raise
    except Exception:
        logger.exception("Acoustic context failed; incident remains active")
        return {
            "ai_context": {
                "status": "UNAVAILABLE",
                "model": None,
                "tags": [],
                "reason": "Acoustic analysis unavailable; incident unchanged.",
            },
            "signed_manifest": None,
        }


@app.post("/api/v1/incidents/{incident_id}/cctv-snapshot")
async def capture_cctv_snapshot(
    incident_id: UUID,
    payload: CctvSnapshotPayload,
    responder_id: str = Depends(require_responder),
):
    """Capture and sign a frame from an authorized nearby camera (<=150m, online, opt-in)."""
    from urllib.request import urlopen as _urlopen

    client = get_db()
    rows = _result_data(client.table("incidents").select("id,lat,lng").eq("id", str(incident_id)).limit(1))
    if not rows:
        raise HTTPException(status_code=404, detail="Incident not found")
    inc = rows[0]
    authorized = _nearby_cameras(
        client,
        IncidentTriggerPayload(
            user_id="system-check",
            trigger_type="EXPLICIT_SOS",
            lat=float(inc["lat"]),
            lng=float(inc["lng"]),
        ),
    )
    matched = next((cam for cam in authorized if str(cam.get("id")) == str(payload.camera_id)), None)
    if not matched:
        raise HTTPException(
            status_code=403,
            detail="Camera is outside the 150m radius or not authorized for this incident",
        )
    stream_url = str(matched.get("stream_url", ""))
    owner_name = str(matched.get("owner_name", payload.camera_id))
    now_utc = datetime.now(timezone.utc).isoformat()
    frame_bytes: bytes | None = None
    demo_fallback = False
    if stream_url.startswith(("http://", "https://")):
        try:
            with _urlopen(stream_url, timeout=2.0) as resp:
                chunk = resp.read(65536)
                if chunk:
                    frame_bytes = chunk
        except Exception:
            logger.info("Live CCTV stream %s unreachable; checking demo fallback", stream_url)
    if not frame_bytes:
        if os.getenv("DEMO_MODE", "false").lower() == "true":
            demo_fallback = True
            frame_bytes = (
                f"MOKGOSI_DEMO_CCTV_SNAPSHOT|incident={incident_id}|camera={payload.camera_id}|"
                f"owner={owner_name}|utc={now_utc}"
            ).encode("utf-8")
        else:
            raise HTTPException(status_code=502, detail="Authorized camera stream is unreachable")
    storage_key = f"incidents/{incident_id}/cctv-{payload.camera_id}-{int(time.time() * 1000)}.bin"
    stored_path = _store_media_bytes(client, storage_key, frame_bytes, "image/jpeg")
    provenance = f"AUTHORIZED_CCTV:{owner_name}:{'DEMO_FALLBACK' if demo_fallback else 'LIVE_STREAM'}"
    manifest = sign_manifest(
        PRIVATE_KEY,
        str(incident_id),
        frame_bytes,
        "AUTHORIZED_CCTV_FRAME",
        provenance,
        now_utc,
        media_storage_path=stored_path,
    )
    persisted = _persist_manifest(client, manifest)
    _audit(
        client,
        str(incident_id),
        responder_id,
        "CCTV_SNAPSHOT_CAPTURED",
        {"camera_id": payload.camera_id, "owner_name": owner_name, "demo_fallback": demo_fallback},
    )
    return {"manifest": persisted, "camera": matched, "demo_fallback": demo_fallback}


class DeviceRegisterPayload(BaseModel):
    preferred_language: Literal["en", "tn"] = "en"


@app.post("/api/v1/devices/register")
async def register_device(
    payload: DeviceRegisterPayload,
    request: Request,
    x_device_key: Optional[str] = Header(default=None),
):
    """Create an anonymous identity: a random user_id plus a per-device token. No name, email, phone or
    national ID is collected. The token is returned once; only its SHA-256 is stored."""
    _check_app_key(x_device_key)
    _consume(f"register:{_client_ip(request)}", REGISTRATIONS_PER_IP_PER_HOUR, window_seconds=3600)
    try:
        client = get_db()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Registration unavailable; the app keeps working unregistered") from exc
    user_id, token = str(uuid4()), secrets.token_urlsafe(32)
    try:
        client.table("survivor_profiles").insert({"user_id": user_id, "preferred_language": payload.preferred_language}).execute()
        rows = _result_data(client.table("devices").insert({
            "user_id": user_id, "device_key_hash": _hash_device_token(token), "active": True,
        }))
    except Exception as exc:
        logger.exception("Device registration insert failed")
        raise HTTPException(status_code=503, detail="Registration unavailable; the app keeps working unregistered") from exc
    device_id = str(rows[0]["id"]) if rows else None
    _audit(client, None, f"device:{device_id}", "DEVICE_REGISTERED", {"user_id": user_id})
    return {"user_id": user_id, "device_id": device_id, "device_token": token}


@app.delete("/api/v1/me/data")
async def delete_my_data(device: DeviceContext = Depends(require_registered_device)):
    """Delete this survivor's personal records for real. Append-only manifests and audit logs stay (they
    hold hashes and actions, no content), as do incident records, which carry only the random user_id."""
    user_id = str(device.user_id)
    try:
        client = get_db()
        bucket = os.getenv("EVIDENCE_STORAGE_BUCKET", "evidence-media")
        entries = _result_data(client.table("evidence_entries").select("id,storage_path").eq("user_id", user_id))
        paths = [row["storage_path"] for row in entries if row.get("storage_path")]
        storage_removed = True
        if paths:
            try:
                client.storage.from_(bucket).remove(paths)
            except Exception:
                storage_removed = False
                logger.warning("Evidence media removal failed for a data-deletion request")
        deleted = {
            "trusted_contacts": len(_result_data(client.table("trusted_contacts").delete().eq("user_id", user_id))),
            "evidence_entries": len(_result_data(client.table("evidence_entries").delete().eq("user_id", user_id))),
            "user_consents": len(_result_data(client.table("user_consents").delete().eq("user_id", user_id))),
            "survivor_profiles": len(_result_data(client.table("survivor_profiles").delete().eq("user_id", user_id))),
            # Last, so every token for this identity stops working.
            "devices": len(_result_data(client.table("devices").delete().eq("user_id", user_id))),
        }
    except Exception as exc:
        logger.exception("Data deletion failed")
        raise HTTPException(status_code=503, detail="Data deletion could not be completed; nothing was confirmed") from exc
    _audit(client, None, f"user:{user_id}", "USER_DATA_DELETED", {
        "deleted_counts": deleted, "evidence_media_objects": len(paths), "evidence_media_removed": storage_removed,
    })
    return {
        "status": "DELETED" if storage_removed else "DELETED_EXCEPT_MEDIA",
        "deleted": deleted,
        "evidence_media_removed": storage_removed,
        "retained": ["incidents (random user_id only)", "evidence_manifests (hashes, append-only)",
                     "evidence_audit_logs (append-only)"],
    }


@app.patch("/api/v1/incidents/{incident_id}/lifecycle")
async def update_incident_lifecycle(incident_id: UUID, payload: LifecycleUpdatePayload,
                                    responder_id: str = Depends(require_responder)):
    client = get_db()
    try:
        current_rows = _result_data(client.table("incidents").select("*").eq("id", str(incident_id)).limit(1))
        if not current_rows:
            raise HTTPException(status_code=404, detail="Incident not found")
        current = current_rows[0]
        expected = NEXT_STATUS.get(current["status"])
        if payload.new_status != expected:
            raise HTTPException(status_code=409, detail=f"Illegal lifecycle transition {current['status']} -> {payload.new_status}")
        now = datetime.now(timezone.utc).isoformat()
        fields: dict[str, Any] = {"status": payload.new_status}
        if payload.new_status == "ACKNOWLEDGED":
            fields.update({"acknowledged_by": responder_id, "acknowledged_at": now})
        elif payload.new_status == "ASSIGNED":
            fields.update({"assigned_to": responder_id, "assigned_at": now})
        elif payload.new_status == "DISPATCHED":
            fields["dispatched_at"] = now
        elif payload.new_status == "RESOLVED":
            fields["resolved_at"] = now
        rows = _result_data(client.table("incidents").update(fields).eq("id", str(incident_id)))
        if not rows:
            raise HTTPException(status_code=404, detail="Incident not found")
        _audit(client, str(incident_id), responder_id, f"LIFECYCLE_{payload.new_status}", {"timestamp_utc": now})
        return {"incident": rows[0]}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Lifecycle update failed")
        raise HTTPException(status_code=503, detail="Lifecycle update failed") from exc


@app.post("/api/v1/incidents/{incident_id}/audit")
async def audit_incident_view(incident_id: UUID, payload: dict[str, str], actor_id: str = Depends(require_responder)):
    action = payload.get("action", "")
    if action not in {"VIEW_INCIDENT", "OPEN_CCTV_STREAM", "VIEW_EVIDENCE"}:
        raise HTTPException(status_code=422, detail="Unsupported audit action")
    try:
        client = get_db()
        recorded = _audit(client, str(incident_id), actor_id, action, {})
        if not recorded:
            raise HTTPException(status_code=503, detail="Audit event could not be persisted")
        return {"recorded": recorded, "actor_id": actor_id, "action": action}
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Audit event could not be persisted") from exc


# =============================================================================
# Pillar B: Safe Network Contacts
# =============================================================================

def _owned_contact(client: Client, contact_id: UUID, device: DeviceContext) -> dict[str, Any]:
    rows = _result_data(client.table("trusted_contacts").select("id,user_id").eq("id", str(contact_id)).limit(1))
    if not rows or rows[0].get("user_id") != device.user_id:
        # Same answer for "missing" and "someone else's", so contact IDs cannot be probed.
        raise HTTPException(status_code=404, detail="Trusted contact not found")
    return rows[0]


@app.post("/api/v1/network/contacts")
async def create_trusted_contact(payload: TrustedContactCreatePayload,
                                 device: DeviceContext = Depends(require_registered_device)):
    """Create a trusted contact in the user's safe network (max 5 active contacts per user)."""
    user_id = _require_owner(device, payload.user_id)
    client = get_db()
    existing = _result_data(
        client.table("trusted_contacts").select("id").eq("user_id", user_id).eq("is_active", True)
    )
    if len(existing) >= 5:
        raise HTTPException(status_code=400, detail="A user may have at most 5 active trusted contacts")
    row = {
        "user_id": user_id,
        "name": payload.name,
        "phone_e164": payload.phone_e164,
        "role": payload.role,
        "priority": payload.priority,
        "notify_on": payload.notify_on,
        "is_active": True,
        "verified": False,
    }
    data = _result_data(client.table("trusted_contacts").insert(row))
    created = data[0] if data else row
    _audit(client, None, f"user:{payload.user_id}", "SAFE_NETWORK_CONTACT_ADDED", {"contact_id": created.get("id"), "role": payload.role, "priority": payload.priority})
    return {"contact": created}


@app.get("/api/v1/network/contacts")
async def list_trusted_contacts(user_id: Optional[str] = None,
                                device: DeviceContext = Depends(require_registered_device)):
    """List the calling device's safe network contacts ordered by priority."""
    owner = _require_owner(device, user_id)
    client = get_db()
    contacts = _result_data(
        client.table("trusted_contacts")
        .select("*")
        .eq("user_id", owner)
        .eq("is_active", True)
        .order("priority", desc=False)
    )
    return {"contacts": contacts}


@app.patch("/api/v1/network/contacts/{contact_id}")
async def update_trusted_contact(contact_id: UUID, payload: TrustedContactUpdatePayload,
                                 device: DeviceContext = Depends(require_registered_device)):
    """Update priority, role, or phone for one of the caller's own safe network contacts."""
    client = get_db()
    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(status_code=422, detail="No fields provided for update")
    _owned_contact(client, contact_id, device)
    data = _result_data(client.table("trusted_contacts").update(updates).eq("id", str(contact_id)).eq("user_id", device.user_id))
    if not data:
        raise HTTPException(status_code=404, detail="Trusted contact not found")
    _audit(client, None, f"user:{device.user_id}", "CONTACT_UPDATED", {"contact_id": str(contact_id)})
    return {"contact": data[0]}


@app.delete("/api/v1/network/contacts/{contact_id}")
async def delete_trusted_contact(contact_id: UUID, device: DeviceContext = Depends(require_registered_device)):
    """Soft-delete one of the caller's own trusted contacts by marking is_active=False."""
    client = get_db()
    _owned_contact(client, contact_id, device)
    data = _result_data(client.table("trusted_contacts").update({"is_active": False}).eq("id", str(contact_id)).eq("user_id", device.user_id))
    if not data:
        raise HTTPException(status_code=404, detail="Trusted contact not found")
    _audit(client, None, f"user:{device.user_id}", "CONTACT_REMOVED", {"contact_id": str(contact_id)})
    return {"deleted": True, "contact_id": str(contact_id)}


# =============================================================================
# Pillar B: Signed Acknowledgement Link (One-Click "I've got this")
# =============================================================================

@app.get("/ack/{token}", response_class=HTMLResponse)
async def ack_get(token: str):
    """Serve tiny, neutral acknowledgement web page with a single 'I've got this' confirmation button."""
    try:
        info = verify_ack_token(token)
    except ValueError as exc:
        return HTMLResponse(
            status_code=400,
            content=f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mokgosi Alert Link</title>
<style>body{{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#f8fafc;padding:2rem;text-align:center;}}
.card{{max-width:440px;margin:3rem auto;padding:2rem;background:#1e293b;border-radius:12px;border:1px solid #ef4444;}}
h2{{color:#ef4444;margin-top:0;}}p{{color:#cbd5e1;line-height:1.6;}}</style>
</head><body><div class="card"><h2>Alert Link Expired or Invalid</h2><p>{str(exc)}</p></div></body></html>""",
        )

    # Check if already acknowledged
    client = None
    already_acked = False
    try:
        client = get_db()
        rows = _result_data(
            client.table("incident_notifications")
            .select("status,acked_at")
            .eq("incident_id", info["incident_id"])
            .eq("contact_id", info["contact_id"])
            .limit(1)
        )
        if rows and rows[0].get("status") == "ACKNOWLEDGED":
            already_acked = True
    except Exception:
        pass

    if already_acked:
        return HTMLResponse(
            content="""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mokgosi Alert - Acknowledged</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#f8fafc;padding:2rem;text-align:center;}
.card{max-width:440px;margin:3rem auto;padding:2rem;background:#1e293b;border-radius:12px;border:1px solid #22c55e;}
h2{color:#22c55e;margin-top:0;}p{color:#cbd5e1;line-height:1.6;}</style>
</head><body><div class="card"><h2>Already Acknowledged</h2><p>You have already acknowledged this safety alert. Your network has recorded your response.</p></div></body></html>"""
        )

    return HTMLResponse(
        content=f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mokgosi Safe Network</title>
<style>
body{{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#f8fafc;padding:2rem;text-align:center;margin:0;}}
.card{{max-width:440px;margin:3rem auto;padding:2.5rem 2rem;background:#1e293b;border-radius:14px;border:1px solid #334155;box-shadow:0 10px 25px rgba(0,0,0,0.5);}}
h2{{color:#38bdf8;margin-top:0;font-size:1.5rem;}}
p{{color:#94a3b8;line-height:1.6;font-size:1.05rem;}}
button{{background:#0284c7;color:#fff;font-size:1.2rem;font-weight:700;padding:1.1rem 2rem;border:none;border-radius:10px;cursor:pointer;width:100%;margin-top:1.75rem;transition:background 0.2s;}}
button:hover{{background:#0369a1;}}
</style>
</head><body><div class="card">
<h2>Mokgosi Safe Network</h2>
<p>Someone in your trusted circle requested an urgent safety check.</p>
<p>Please confirm that you have seen this alert and are following up.</p>
<form method="POST" action="/ack/{token}">
<button type="submit">I've got this</button>
</form>
</div></body></html>"""
    )


@app.post("/ack/{token}", response_class=HTMLResponse)
async def ack_post(token: str):
    """Handle one-click acknowledgement submission."""
    try:
        info = verify_ack_token(token)
    except ValueError as exc:
        return HTMLResponse(status_code=400, content=f"<h2>Error</h2><p>{str(exc)}</p>")

    now_utc = datetime.now(timezone.utc).isoformat()
    try:
        client = get_db()
        client.table("incident_notifications").update({
            "status": "ACKNOWLEDGED",
            "acked_at": now_utc,
        }).eq("incident_id", info["incident_id"]).eq("contact_id", info["contact_id"]).execute()
        _audit(client, info["incident_id"], f"contact:{info['contact_id']}", "TRUSTED_CONTACT_ACKNOWLEDGED", {
            "acked_at": now_utc,
            "contact_id": info["contact_id"],
        })
    except Exception:
        logger.exception("Failed to write acknowledgement to DB; responding to contact with confirmation")

    return HTMLResponse(
        content="""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mokgosi Alert - Confirmed</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;background:#0f172a;color:#f8fafc;padding:2rem;text-align:center;}
.card{max-width:440px;margin:3rem auto;padding:2rem;background:#1e293b;border-radius:12px;border:1px solid #22c55e;}
h2{color:#22c55e;margin-top:0;}p{color:#cbd5e1;line-height:1.6;}</style>
</head><body><div class="card"><h2>Thank You</h2><p>Your acknowledgement was recorded. Your safe network has been notified that you are responding.</p></div></body></html>"""
    )


# =============================================================================
# Pillar B: Survivor-Owned Evidence Vault & Case Bundles
# =============================================================================

@app.post("/api/v1/evidence-entries")
async def store_evidence_entry(
    kind: Literal["AUDIO", "PHOTO", "NOTE"] = Form(...),
    user_id: Optional[str] = Form(None),
    source_capture_utc: Optional[str] = Form(None),
    lat: Optional[float] = Form(None),
    lng: Optional[float] = Form(None),
    notes: Optional[str] = Form(None),
    media_file: Optional[UploadFile] = File(None),
    device: DeviceContext = Depends(require_registered_device),
):
    """Store survivor-owned media or note; sign cryptographic manifest with persistent Ed25519 key."""
    user_id = _require_owner(device, user_id)
    client = get_db()
    now_utc = source_capture_utc or datetime.now(timezone.utc).isoformat()

    raw_bytes: bytes = b""
    content_type = "text/plain"
    filename = f"entry_{int(time.time() * 1000)}"
    if media_file is not None:
        raw_bytes = await media_file.read()
        content_type = media_file.content_type or "application/octet-stream"
        filename = media_file.filename or filename
    elif notes:
        raw_bytes = notes.encode("utf-8")

    if not raw_bytes:
        raise HTTPException(status_code=422, detail="Either media_file or notes content must be provided")

    storage_path = f"evidence-vault/{user_id}/{filename}"
    _store_media_bytes(client, storage_path, raw_bytes, content_type)

    media_type_map = {
        "AUDIO": "SURVIVOR_AUDIO",
        "PHOTO": "SURVIVOR_PHOTO",
        "NOTE": "SURVIVOR_NOTE",
    }
    manifest = sign_manifest(
        PRIVATE_KEY,
        incident_id=f"survivor:{user_id}",
        content=raw_bytes,
        media_type=media_type_map[kind],
        provenance=f"SURVIVOR_VAULT:{lat},{lng}" if lat is not None else "SURVIVOR_VAULT:NO_GPS",
        source_ts=now_utc,
        media_storage_path=storage_path,
    )
    persisted_manifest = _persist_manifest(client, manifest)
    manifest_id = persisted_manifest.get("id")

    entry_row = {
        "user_id": user_id,
        "kind": kind,
        "captured_at_utc": now_utc,
        "lat": lat,
        "lng": lng,
        "notes": notes,
        "_raw_bytes": raw_bytes,
        "storage_path": storage_path,
        "manifest_id": manifest_id,
        "shared_with": [],
        "deleted_at": None,
    }
    if lat is not None and lng is not None:
        entry_row["gps"] = f"POINT({lng} {lat})"

    data = _result_data(client.table("evidence_entries").insert(entry_row))
    created_entry = data[0] if data else entry_row

    _audit(client, None, f"user:{user_id}", "SURVIVOR_EVIDENCE_STORED", {
        "entry_id": created_entry.get("id"),
        "kind": kind,
        "manifest_id": manifest_id,
    })
    return {"entry": created_entry, "signed_manifest": persisted_manifest}


@app.get("/api/v1/evidence-entries")
async def list_evidence_entries(
    user_id: Optional[str] = Query(None),
    device: DeviceContext = Depends(require_registered_device),
):
    """List caller's active evidence entries (user cannot read another user's entries)."""
    user_id = _require_owner(device, user_id)
    client = get_db()
    rows = _result_data(
        client.table("evidence_entries")
        .select("*")
        .eq("user_id", user_id)
        .is_("deleted_at", "null")
        .order("captured_at_utc", desc=True)
    )
    return {"entries": rows}


@app.delete("/api/v1/evidence-entries/{entry_id}")
async def delete_evidence_entry(
    entry_id: UUID,
    hard_delete: bool = Query(False),
    device: DeviceContext = Depends(require_registered_device),
):
    """Soft-delete (and optional hard-delete) an evidence entry; log action honestly without content."""
    client = get_db()
    rows = _result_data(client.table("evidence_entries").select("*").eq("id", str(entry_id)).limit(1))
    if not rows or rows[0].get("user_id") != device.user_id:
        raise HTTPException(status_code=404, detail="Evidence entry not found")
    entry = rows[0]

    now_utc = datetime.now(timezone.utc).isoformat()
    client.table("evidence_entries").update({"deleted_at": now_utc}).eq("id", str(entry_id)).execute()

    if hard_delete and entry.get("storage_path"):
        try:
            bucket = os.getenv("EVIDENCE_STORAGE_BUCKET", "evidence-media")
            storage = getattr(client, "storage", None)
            if storage:
                storage.from_(bucket).remove([entry["storage_path"]])
        except Exception:
            logger.warning("Hard delete storage removal failed for %s", entry.get("storage_path"))

    _audit(client, None, f"user:{entry['user_id']}", "SURVIVOR_EVIDENCE_DELETED", {
        "entry_id": str(entry_id),
        "hard_delete": hard_delete,
    })
    return {"deleted": True, "entry_id": str(entry_id), "hard_delete": hard_delete, "deleted_at": now_utc}


@app.post("/api/v1/evidence-entries/share")
async def share_evidence_bundle(
    payload: EvidenceSharePayload,
    device: DeviceContext = Depends(require_registered_device),
):
    """Produce a signed forensic case bundle ZIP with expiring download token. No auto-sharing."""
    owner = _require_owner(device, payload.user_id)
    payload = payload.model_copy(update={"user_id": owner})
    client = get_db()
    entries = []
    manifests = []

    for eid in payload.entry_ids:
        rows = _result_data(
            client.table("evidence_entries")
            .select("*")
            .eq("id", eid)
            .eq("user_id", payload.user_id)
            .is_("deleted_at", "null")
            .limit(1)
        )
        if not rows:
            raise HTTPException(status_code=404, detail=f"Evidence entry {eid} not found or not owned by caller")
        entry = rows[0]
        entries.append(entry)
        if entry.get("manifest_id"):
            m_rows = _result_data(client.table("evidence_manifests").select("*").eq("id", entry["manifest_id"]).limit(1))
            if m_rows:
                m_dict = dict(m_rows[0])
                # Each manifest carries the key that signed it, which after rotation may be a retired one.
                signer = KEYRING.get(str(m_dict.get("public_key_id")))
                if signer:
                    m_dict["public_key"] = signer["public_key"]
                manifests.append(m_dict)

    bundle_id = str(uuid4())
    zip_bytes = generate_case_bundle_zip(payload.user_id, entries, manifests, payload.recipient_type, payload.notes)
    token = generate_bundle_token(payload.user_id, bundle_id, ttl_seconds=7200)

    # Cache bundle in-memory for download link
    _bundle_cache[token] = {
        "user_id": payload.user_id,
        "bundle_id": bundle_id,
        "zip_bytes": zip_bytes,
        "recipient_type": payload.recipient_type,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    # Record share metadata on each entry
    now_utc = datetime.now(timezone.utc).isoformat()
    for entry in entries:
        existing_shared = entry.get("shared_with") or []
        existing_shared.append({
            "recipient_type": payload.recipient_type,
            "shared_at": now_utc,
            "bundle_id": bundle_id,
        })
        client.table("evidence_entries").update({"shared_with": existing_shared}).eq("id", entry["id"]).execute()

    _audit(client, None, f"user:{payload.user_id}", "EVIDENCE_BUNDLE_GENERATED", {
        "bundle_id": bundle_id,
        "recipient_type": payload.recipient_type,
        "entry_count": len(entries),
    })

    return {
        "bundle_id": bundle_id,
        "download_url": f"/api/v1/evidence-bundles/{token}",
        "recipient_type": payload.recipient_type,
        "entry_count": len(entries),
        "expires_in_seconds": 7200,
    }


@app.get("/api/v1/evidence-bundles/{token}")
async def download_case_bundle(token: str):
    """Download an expiring case bundle ZIP; audit-log every access."""
    try:
        info = verify_bundle_token(token)
    except ValueError as exc:
        raise HTTPException(status_code=403, detail=str(exc))

    cached = _bundle_cache.get(token)
    if not cached:
        raise HTTPException(status_code=404, detail="Case bundle has expired or is no longer in cache")

    try:
        client = get_db()
        _audit(client, None, "EXTERNAL_RECIPIENT", "EVIDENCE_BUNDLE_DOWNLOADED", {
            "bundle_id": info["bundle_id"],
            "user_id": info["user_id"],
        })
    except Exception:
        pass

    filename = f"mokgosi-case-bundle-{info['bundle_id'][:8]}.zip"
    return Response(
        content=cached["zip_bytes"],
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


# =============================================================================
# Pillar B: Referral Directory & Incident Case Handoffs
# =============================================================================

@app.get("/api/v1/referrals")
async def list_referral_partners(
    region: Optional[str] = Query(None),
    type: Optional[str] = Query(None),
):
    """Survivor-facing referral directory: returns STRICTLY verified partners only."""
    client = get_db()
    query = client.table("referral_partners").select("*").eq("verified", True)
    if region:
        query = query.eq("region", region)
    if type:
        query = query.eq("type", type)
    rows = _result_data(query)
    # Notice: unverified entries are completely suppressed from this endpoint!
    return {"partners": rows, "count": len(rows)}


@app.get("/api/v1/incidents/{incident_id}/referrals")
async def list_incident_referrals(incident_id: UUID, _responder: str = Depends(require_responder)):
    """Responder-facing: list referral handoffs recorded for this incident."""
    client = get_db()
    rows = _result_data(
        client.table("incident_referrals")
        .select("id,incident_id,partner_id,referred_by,referred_at,outcome,notes")
        .eq("incident_id", str(incident_id))
        .order("referred_at", desc=True)
    )
    return {"referrals": rows}


@app.post("/api/v1/incidents/{incident_id}/referrals")
async def record_incident_referral(
    incident_id: UUID,
    payload: ReferralCreatePayload,
    responder_id: str = Depends(require_responder),
):
    """Responder-facing: record a referral action (audit-logged append-only record)."""
    client = get_db()
    partner_rows = _result_data(client.table("referral_partners").select("id,name,type").eq("id", str(payload.partner_id)).limit(1))
    if not partner_rows:
        raise HTTPException(status_code=404, detail="Referral partner organization not found")
    partner = partner_rows[0]

    now_utc = datetime.now(timezone.utc).isoformat()
    row = {
        "incident_id": str(incident_id),
        "partner_id": str(payload.partner_id),
        "referred_by": responder_id,
        "referred_at": now_utc,
        "outcome": "REFERRED",
        "notes": payload.notes,
    }
    data = _result_data(client.table("incident_referrals").insert(row))
    created = data[0] if data else row

    _audit(client, str(incident_id), responder_id, "INCIDENT_REFERRED_TO_PARTNER", {
        "partner_id": str(payload.partner_id),
        "partner_name": partner.get("name"),
        "partner_type": partner.get("type"),
        "notes": payload.notes,
    })
    return {"referral": created}


# =============================================================================
# Pillar B: Survivor Consents
# =============================================================================

def _consents_for(client: Client, user_id: str) -> dict[str, Any]:
    rows = _result_data(client.table("user_consents").select("*").eq("user_id", user_id).limit(1))
    if rows:
        return rows[0]
    return {"user_id": user_id, "location": True, "audio": False, "responder_contact": False,
            "share_evidence": False, "recorded": False}


@app.get("/api/v1/me/consents")
async def get_my_consents(device: DeviceContext = Depends(require_registered_device)):
    """Retrieve the calling survivor's consent toggles."""
    return {"consents": _consents_for(get_db(), str(device.user_id))}


@app.get("/api/v1/consents/{user_id}")
async def get_user_consents(user_id: str, device: DeviceContext = Depends(require_registered_device)):
    """Retrieve survivor consent toggles."""
    return {"consents": _consents_for(get_db(), _require_owner(device, user_id))}


@app.patch("/api/v1/consents")
async def update_user_consents(payload: ConsentsUpdatePayload, device: DeviceContext = Depends(require_registered_device)):
    """Update survivor consent toggles. DURESS/COVERT always overrides responder contact."""
    payload = payload.model_copy(update={"user_id": _require_owner(device, payload.user_id)})
    client = get_db()
    now_utc = datetime.now(timezone.utc).isoformat()
    row = {
        "user_id": payload.user_id,
        "location": payload.location if payload.location is not None else True,
        "audio": payload.audio if payload.audio is not None else False,
        "responder_contact": payload.responder_contact if payload.responder_contact is not None else False,
        "share_evidence": payload.share_evidence if payload.share_evidence is not None else False,
        "updated_at": now_utc,
    }
    # Upsert pattern
    existing = _result_data(client.table("user_consents").select("user_id").eq("user_id", payload.user_id).limit(1))
    if existing:
        data = _result_data(client.table("user_consents").update(row).eq("user_id", payload.user_id))
    else:
        data = _result_data(client.table("user_consents").insert(row))

    _audit(client, None, f"user:{payload.user_id}", "USER_CONSENTS_UPDATED", {
        "location": row["location"],
        "audio": row["audio"],
        "responder_contact": row["responder_contact"],
        "share_evidence": row["share_evidence"],
    })
    return {"consents": data[0] if data else row}


# =============================================================================
# Pillar A & B: Coarse Grid Analytics / Hotspots (Safer Communities View)
# =============================================================================

@app.get("/api/v1/analytics/hotspots")
async def get_analytics_hotspots():
    """Aggregated coarse grid hotspots (~500m) with strict k-anonymity suppression."""
    client = get_db()
    incidents = _result_data(
        client.table("incidents")
        .select("lat,lng,category,created_at")
        .limit(1000)
    )
    hotspots = aggregate_hotspots(incidents)
    return {
        "hotspots": hotspots,
        "cell_count": len(hotspots),
        "privacy_guarantee": "K-anonymity: cells < 5 public incidents (or < 10 GBV incidents) suppressed; coordinates coarsened to ~500m.",
    }
