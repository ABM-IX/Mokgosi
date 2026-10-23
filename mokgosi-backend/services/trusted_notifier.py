"""Trusted-person notification adapters with bounded retry and clear outcomes."""

import base64
import json
import logging
import os
import re
import time
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen

logger = logging.getLogger("mokgosi.notifier")
E164 = re.compile(r"^\+[1-9][0-9]{7,14}$")


def _deliver_console(message: dict[str, Any]) -> None:
    logger.info("DEMO ONLY: trusted-person notification not delivered: %s", json.dumps(message, sort_keys=True))


def _deliver_webhook(message: dict[str, Any]) -> None:
    endpoint = os.getenv("TRUSTED_NOTIFIER_WEBHOOK_URL", "")
    if not endpoint:
        raise RuntimeError("TRUSTED_NOTIFIER_WEBHOOK_URL is not configured")
    request = Request(endpoint, data=json.dumps(message).encode(), headers={"Content-Type": "application/json"}, method="POST")
    with urlopen(request, timeout=5) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"Notifier webhook returned HTTP {response.status}")


def _deliver_twilio(message: dict[str, Any]) -> None:
    """Send one-way international SMS through Twilio Programmable Messaging."""
    account = os.getenv("TWILIO_ACCOUNT_SID", "")
    token = os.getenv("TWILIO_AUTH_TOKEN", "")
    sender = os.getenv("TWILIO_FROM", "")
    if not (account and token and sender):
        raise RuntimeError("Twilio SMS credentials or TWILIO_FROM are missing")
    body = (
        f"MOKGOSI {message['priority']}: {message['user_id']} needs a check. "
        f"Reason: {message['trigger_reason']}. Latest location: {message['maps_url']}"
    )
    data = urlencode({"To": message["recipient"], "From": sender, "Body": body}).encode()
    auth = base64.b64encode(f"{account}:{token}".encode()).decode()
    request = Request(
        f"https://api.twilio.com/2010-04-01/Accounts/{account}/Messages.json",
        data=data,
        headers={"Authorization": f"Basic {auth}", "Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urlopen(request, timeout=8) as response:
        if response.status < 200 or response.status >= 300:
            raise RuntimeError(f"Twilio returned HTTP {response.status}")


PROVIDERS = {"console": _deliver_console, "webhook": _deliver_webhook, "twilio": _deliver_twilio}


def validate_e164(phone: str) -> str:
    if not E164.fullmatch(phone):
        raise ValueError("trusted_contact_phone must be in E.164 format")
    return phone


def dispatch(
    incident_id: str,
    user_id: str,
    phone: str,
    trigger: str,
    priority: str,
    lat: float,
    lng: float,
    *,
    provider: str | None = None,
    attempts: int = 3,
    backoff_seconds: float = 0.25,
) -> dict[str, Any]:
    """Try delivery up to three times and return a truthful outcome."""
    validate_e164(phone)
    selected = (provider or os.getenv("NOTIFIER_PROVIDER", "console")).lower()
    if selected not in PROVIDERS:
        raise ValueError("NOTIFIER_PROVIDER must be console, webhook, or twilio")
    message = {
        "recipient": phone,
        "user_id": user_id,
        "trigger_reason": trigger,
        "priority": priority,
        "maps_url": f"https://www.google.com/maps?q={lat},{lng}",
        "incident_id": incident_id,
    }
    last_error: Exception | None = None
    for attempt in range(max(1, attempts)):
        try:
            PROVIDERS[selected](message)
            return {"success": True, "provider": selected, "attempts": attempt + 1, "message": message}
        except Exception as exc:  # provider exceptions must not suppress incident handling
            last_error = exc
            logger.warning("Trusted-person delivery attempt %s failed: %s", attempt + 1, exc)
            if attempt + 1 < attempts:
                time.sleep(backoff_seconds * (2**attempt))
    return {
        "success": False,
        "provider": selected,
        "attempts": max(1, attempts),
        "error": str(last_error or "delivery failed"),
        "message": message,
    }
