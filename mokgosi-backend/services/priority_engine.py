def assign_initial_priority(trigger_type: str, impact_g: float = 1.0) -> str:
    if trigger_type in {"EXPLICIT_SOS", "DURESS_PIN", "COVERT_SOS", "SHAKE_SOS"}:
        return "P1_CRITICAL"
    if trigger_type == "MOTION_IMPACT" or impact_g >= 3.5:
        return "P2_HIGH"
    return "P3_VERIFY"
