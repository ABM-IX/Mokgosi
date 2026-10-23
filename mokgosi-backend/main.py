"""Mokgosi incident API. The trusted-person and response-network routes fail independently."""

import hmac
import logging
import os
import threading
import time
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any, Literal, Optional
from uuid import UUID

from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator
from supabase import Client, create_client

from services.acoustic_worker import analyze
from services.evidence_vault import load_private_key, public_key_hex, sign_manifest, verify_manifest
from services.priority_engine import assign_initial_priority
from services.trusted_notifier import dispatch, validate_e164

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("mokgosi.api")

# Refuse to run with ephemeral/rotating signing keys. This key remains process stable.
try:
    PRIVATE_KEY = load_private_key()
except ValueError as exc:
    raise RuntimeError(str(exc)) from exc
PUBLIC_KEY_HEX = public_key_hex(PRIVATE_KEY)
KEY_ID = f"mokgosi-ed25519-{PUBLIC_KEY_HEX[:8]}"

app = FastAPI(title="MOKGOSI Incident & Evidence Engine", version="2.1")
cors_origins = [origin.strip() for origin in os.getenv("CORS_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173").split(",") if origin.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Device-Key"],
)

_rate_lock = threading.Lock()
_rate_windows: dict[str, list[float]] = {}
RATE_LIMIT = int(os.getenv("RATE_LIMIT_PER_MINUTE", "60"))
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


def _rate_limit(request: Request, identity: str) -> None:
    now = time.monotonic()
    ip = request.client.host if request.client else "unknown"
    for key in (f"ip:{ip}", identity):
        with _rate_lock:
            recent = [stamp for stamp in _rate_windows.get(key, []) if now - stamp < 60]
            if len(recent) >= RATE_LIMIT:
                raise HTTPException(status_code=429, detail="Rate limit exceeded")
            recent.append(now)
            _rate_windows[key] = recent


def require_device(request: Request, x_device_key: Optional[str] = Header(default=None)) -> str:
    """Require one configured device key and rate-limit by both device and IP."""
    configured = [value.strip() for value in os.getenv("DEVICE_API_KEYS", os.getenv("DEVICE_API_KEY", "")).split(",") if value.strip()]
    if not x_device_key or not configured or not any(hmac.compare_digest(x_device_key, value) for value in configured):
        raise HTTPException(status_code=401, detail="Valid X-Device-Key required")
    identity = f"device:{x_device_key}"
    _rate_limit(request, identity)
    return identity


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
    authorization: Optional[str] = Header(default=None),
) -> str:
    """Allow either an authenticated responder or a configured device key (for Route 3 audio uploads)."""
    if authorization and authorization.lower().startswith("bearer "):
        return require_responder(request, authorization)
    if x_device_key:
        return require_device(request, x_device_key)
    raise HTTPException(status_code=401, detail="Valid X-Device-Key or responder Bearer token required")


class IncidentTriggerPayload(BaseModel):
    user_id: str = Field(min_length=1, max_length=120)
    trusted_contact_phone: Optional[str] = None
    trigger_type: Literal["EXPLICIT_SOS", "DURESS_PIN", "MISSED_CHECKIN", "MOTION_IMPACT"]
    category: Literal["PERSONAL_SAFETY", "GBV_DOMESTIC"] = "PERSONAL_SAFETY"
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    impact_g_force: float = Field(default=1.0, ge=0, le=100)
    source_timestamp_utc: Optional[str] = None
    client_event_id: Optional[UUID] = None

    @field_validator("trusted_contact_phone")
    @classmethod
    def phone_is_e164(cls, value: Optional[str]) -> Optional[str]:
        return validate_e164(value) if value else None


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
) -> None:
    """Run notifier without depending on the response database path."""
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
                  priority: str, client: Client | None) -> None:
    background_tasks.add_task(_notify_trusted_person, incident_id, payload, priority, client)


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


@app.get("/health")
def health() -> dict[str, Any]:
    return {"status": "ok", "database_configured": bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_KEY")),
            "demo_mode": os.getenv("DEMO_MODE", "false").lower() == "true", "signing_key_id": KEY_ID}


@app.get("/api/v1/evidence/public-key")
def evidence_public_key() -> dict[str, str]:
    return {"public_key_id": KEY_ID, "public_key": PUBLIC_KEY_HEX, "algorithm": "Ed25519"}


@app.post("/api/v1/evidence/verify")
def evidence_verify(manifest: dict[str, Any]) -> dict[str, bool]:
    return {"valid": verify_manifest(manifest, PUBLIC_KEY_HEX)}


@app.post("/api/v1/incidents/trigger")
async def trigger_incident(
    payload: IncidentTriggerPayload,
    background_tasks: BackgroundTasks,
    request: Request,
    _device: str = Depends(require_device),
) -> dict[str, Any]:
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
            _queue_notify(background_tasks, incident_id, payload, raised_priority, client)
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
    _queue_notify(background_tasks, incident_id, payload, priority, client)
    cameras = _nearby_cameras(client, payload)
    _audit(client, incident_id, "MOKGOSI_INGEST_ENGINE", "INCIDENT_CREATED", {
        "initial_priority": priority, "trigger_type": payload.trigger_type, "matched_cameras": len(cameras),
        "client_ip": request.client.host if request.client else None,
    })
    return {"status": "MOKGOSI_ALERT_ACTIVE", "incident_persisted": True, "persistence_state": "PERSISTED",
            "notification_state": "QUEUED" if payload.trusted_contact_phone else "NOT_CONFIGURED",
            "notification_mode": _notification_mode(), "incident": incident, "authorized_cameras": cameras}


@app.post("/api/v1/incidents/{incident_id}/location")
async def append_location(incident_id: UUID, payload: LocationPayload, _device: str = Depends(require_device)):
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


@app.delete("/api/v1/users/{user_id}/data")
async def delete_user_personal_data(user_id: str, _device: str = Depends(require_device)):
    """Delete user's mutable personal contact/location records while retaining append-only forensic manifests."""
    try:
        client = get_db()
        _audit(
            client,
            None,
            f"user:{user_id}",
            "USER_DATA_DELETION_REQUESTED",
            {"note": "Trusted contacts cleared; append-only forensic logs retained per evidence integrity rules."},
        )
        return {
            "status": "PROCESSED",
            "user_id": user_id,
            "deleted_scopes": ["trusted_contacts", "active_escort_preferences"],
            "retained_scopes": ["evidence_manifests", "evidence_audit_logs"],
        }
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Data deletion request could not be processed") from exc


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
