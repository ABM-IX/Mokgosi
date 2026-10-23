"""Safe network management, priority escalation chain, and signed acknowledgement links.

Invariant 1: External SMS provider, persistence, and audit failures fail independently.
Wording for GBV categories is neutral, discreet, and actionable (never graphic).
"""

import base64
import hmac
import hashlib
import json
import logging
import os
import threading
import time
from datetime import datetime, timezone
from typing import Any, Optional
from uuid import UUID

from services.trusted_notifier import dispatch, validate_e164

logger = logging.getLogger("mokgosi.safe_network")
DEFAULT_ESCALATION_SECONDS = float(os.getenv("ESCALATION_SECONDS", "5.0"))
SECRET_SALT = os.getenv("ED25519_PRIVATE_KEY_SEED", "mokgosi-safe-network-default-salt").encode("utf-8")


def generate_ack_token(incident_id: str, contact_id: str, ttl_seconds: int = 3600) -> str:
    """Generate a tamper-evident, expiring acknowledgement token."""
    expires_at = int(time.time()) + ttl_seconds
    payload = f"{incident_id}:{contact_id}:{expires_at}"
    sig = hmac.new(SECRET_SALT, payload.encode("utf-8"), hashlib.sha256).hexdigest()[:32]
    raw = f"{payload}:{sig}"
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("utf-8")


def verify_ack_token(token: str) -> dict[str, Any]:
    """Verify an acknowledgement token. Raises ValueError on expiration, tampering, or malformation."""
    try:
        raw = base64.urlsafe_b64decode(token.encode("utf-8")).decode("utf-8")
        parts = raw.split(":")
        if len(parts) != 4:
            raise ValueError("Malformed acknowledgement token")
        incident_id, contact_id, exp_str, sig = parts
        expires_at = int(exp_str)
        expected_payload = f"{incident_id}:{contact_id}:{expires_at}"
        expected_sig = hmac.new(SECRET_SALT, expected_payload.encode("utf-8"), hashlib.sha256).hexdigest()[:32]
        if not hmac.compare_digest(sig, expected_sig):
            raise ValueError("Invalid or tampered acknowledgement signature")
        if time.time() > expires_at:
            raise ValueError("Acknowledgement link has expired")
        return {"incident_id": incident_id, "contact_id": contact_id, "expires_at": expires_at}
    except Exception as exc:
        if isinstance(exc, ValueError):
            raise
        raise ValueError(f"Invalid token: {exc}") from exc


def format_neutral_sms(
    category: str,
    priority: str,
    user_id: str,
    ack_url: str,
    maps_url: str,
) -> str:
    """Discreet, non-graphic wording for SMS dispatch. Protects survivors if SMS preview is observed."""
    is_gbv = category.startswith("GBV_") or category == "GBV_DOMESTIC"
    if is_gbv:
        # Non-graphic and discreet
        return (
            f"Mokgosi Alert: Someone in your safe network requested an urgent safety check. "
            f"Confirm you are responding: {ack_url} | Location: {maps_url}"
        )
    return (
        f"Mokgosi Safety Alert ({priority}): A check-in was requested for {user_id}. "
        f"Confirm you are responding: {ack_url} | Location: {maps_url}"
    )


def notify_contact_step(
    incident_id: str,
    user_id: str,
    contact: dict[str, Any],
    category: str,
    priority: str,
    lat: float,
    lng: float,
    client: Any,
    base_url: str,
    escalated_from: Optional[str] = None,
    provider: Optional[str] = None,
) -> dict[str, Any]:
    """Notify a single contact in the safe network with an acknowledgement token."""
    contact_id = str(contact.get("id", ""))
    phone = str(contact.get("phone_e164", ""))
    ack_token = generate_ack_token(incident_id, contact_id)
    ack_url = f"{base_url.rstrip('/')}/ack/{ack_token}"
    maps_url = f"https://www.google.com/maps?q={lat},{lng}"

    # Record notification attempt in DB (best-effort; never blocks SMS dispatch)
    notif_row = {
        "incident_id": incident_id,
        "contact_id": contact_id,
        "status": "SENT",
        "attempt": 1,
        "escalated_from": escalated_from,
        "ack_token": ack_token,
        "sent_at": datetime.now(timezone.utc).isoformat(),
    }
    if client:
        try:
            client.table("incident_notifications").insert(notif_row).execute()
        except Exception:
            logger.exception("Failed to insert incident_notification row; continuing SMS dispatch")

    # Send message via trusted notifier provider
    outcome = dispatch(
        incident_id,
        user_id,
        phone,
        trigger=f"{category}:{priority}",
        priority=priority,
        lat=lat,
        lng=lng,
        provider=provider,
    )

    # Best-effort audit logging
    if client:
        try:
            client.table("evidence_audit_logs").insert({
                "incident_id": incident_id,
                "actor_id": "MOKGOSI_SAFE_NETWORK",
                "action": "ESCALATION_NOTIFICATION_DISPATCHED",
                "client_metadata": {
                    "contact_id": contact_id,
                    "priority": contact.get("priority", 1),
                    "escalated_from": escalated_from,
                    "provider": outcome.get("provider"),
                    "success": outcome.get("success"),
                },
            }).execute()
        except Exception:
            logger.exception("Failed to insert audit log for contact notification")

    return {
        "contact_id": contact_id,
        "outcome": outcome,
        "ack_token": ack_token,
        "notif_row": notif_row,
    }


def run_escalation_chain(
    incident_id: str,
    user_id: str,
    category: str,
    priority: str,
    lat: float,
    lng: float,
    client: Any,
    base_url: str = "http://localhost:8000",
    escalation_seconds: Optional[float] = None,
    provider: Optional[str] = None,
) -> list[dict[str, Any]]:
    """Synchronous or thread-executed escalation chain across ordered trusted contacts."""
    timeout = escalation_seconds if escalation_seconds is not None else DEFAULT_ESCALATION_SECONDS
    contacts: list[dict[str, Any]] = []

    if client:
        try:
            res = (
                client.table("trusted_contacts")
                .select("*")
                .eq("user_id", user_id)
                .eq("is_active", True)
                .order("priority", desc=False)
                .execute()
            )
            contacts = getattr(res, "data", None) or []
        except Exception:
            logger.exception("Could not query trusted_contacts for escalation")

    if not contacts:
        logger.info("No active trusted contacts configured for user %s", user_id)
        return []

    # Filter by notify_on scope if configured
    eligible_contacts = []
    for c in contacts:
        notify_on = c.get("notify_on") or []
        if not notify_on or priority in notify_on or category in notify_on:
            eligible_contacts.append(c)

    if not eligible_contacts:
        eligible_contacts = contacts  # Fallback to all active contacts

    # Dispatch to contact 1 (highest priority)
    results = []
    c1 = eligible_contacts[0]
    res1 = notify_contact_step(
        incident_id, user_id, c1, category, priority, lat, lng, client, base_url, provider=provider
    )
    results.append(res1)

    if len(eligible_contacts) > 1 and timeout > 0:
        # Wait escalation delay
        time.sleep(timeout)

        # Check if contact 1 acknowledged
        c1_acked = False
        if client:
            try:
                notif_check = (
                    client.table("incident_notifications")
                    .select("status")
                    .eq("incident_id", incident_id)
                    .eq("contact_id", str(c1.get("id")))
                    .limit(1)
                    .execute()
                )
                data = getattr(notif_check, "data", None) or []
                if data and data[0].get("status") == "ACKNOWLEDGED":
                    c1_acked = True
            except Exception:
                logger.exception("Failed to check contact 1 ack status")

        if not c1_acked:
            # Escalate to contact 2
            c2 = eligible_contacts[1]
            logger.info("Contact 1 did not acknowledge within %ss. Escalating to contact 2", timeout)
            res2 = notify_contact_step(
                incident_id,
                user_id,
                c2,
                category,
                priority,
                lat,
                lng,
                client,
                base_url,
                escalated_from=str(c1.get("id")),
                provider=provider,
            )
            results.append(res2)

    return results
