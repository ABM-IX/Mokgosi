"""Truthfully labelled deterministic acoustic profiles for the hackathon demo."""

PROFILES = {
    "DISTRESSED": {"status": "ANALYZED", "model": "DETERMINISTIC_DEMO", "tags": ["Demo distress profile", "Screaming (0.91)", "Groan / Struggle (0.78)"], "confidence": 0.91, "escalation_action": "UPGRADED_TO_P1_CRITICAL"},
    "CONVERSATION": {"status": "ANALYZED", "model": "DETERMINISTIC_DEMO", "tags": ["Demo conversation profile", "Speech / Conversation (0.88)"], "confidence": 0.88, "escalation_action": "MAINTAINED_FOR_HUMAN_REVIEW"},
    "SILENT": {"status": "ANALYZED", "model": "DETERMINISTIC_DEMO", "tags": ["Demo silent profile", "Silence / Ambiguous Ambient (0.95)"], "confidence": 0.95, "escalation_action": "FLAGGED_SILENT_COERCION_RISK"},
}


def analyze(profile: str) -> dict:
    """Use deterministic demo labels only; a real YAMNet worker is not wired."""
    try:
        return dict(PROFILES[profile.upper()])
    except KeyError as exc:
        raise ValueError("Profile must be DISTRESSED, CONVERSATION, or SILENT") from exc
