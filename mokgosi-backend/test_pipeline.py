"""Manual Stage 1 smoke request: python test_pipeline.py [API_URL]."""

import json
import os
import sys
import urllib.request
from uuid import uuid4


def main() -> None:
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"
    device_key = os.getenv("MOKGOSI_DEVICE_API_KEY")
    if not device_key:
        raise SystemExit("Set MOKGOSI_DEVICE_API_KEY to the device key configured in the backend")
    payload = {
        "user_id": "demo-user-01",
        "trigger_type": "EXPLICIT_SOS",
        "lat": -24.6560,
        "lng": 25.9090,
        "impact_g_force": 1.0,
        "client_event_id": str(uuid4()),
    }
    phone = os.getenv("MOKGOSI_TRUSTED_CONTACT_PHONE")
    if phone:
        payload["trusted_contact_phone"] = phone
    request = urllib.request.Request(
        base + "/api/v1/incidents/trigger",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "X-Device-Key": device_key},
        method="POST",
    )
    with urllib.request.urlopen(request) as response:
        result = json.load(response)
        print(json.dumps(result, indent=2))
        assert result["incident"]["priority"] == "P1_CRITICAL"


if __name__ == "__main__":
    main()
