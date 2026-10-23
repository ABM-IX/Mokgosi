"""Analytics and coarse hotspot aggregation with privacy-preserving k-anonymity suppression.

Rules:
- Cell coordinates are coarsened to ~500m grid cells (0.005 degree step).
- Any grid cell with fewer than 5 incidents is strictly suppressed.
- GBV categories carry a stricter threshold (minimum 10 incidents) to prevent re-identification of private residences.
- Coordinates finer than ~500m, user_ids, and exact timestamps are NEVER leaked.
"""

from collections import defaultdict
from typing import Any

GRID_STEP = 0.005  # ~555 meters coarse resolution
MIN_THRESHOLD_PUBLIC = 5
MIN_THRESHOLD_GBV = 10


def coarsen_coord(lat: float, lng: float, step: float = GRID_STEP) -> tuple[float, float]:
    """Snap coordinates to the center of a coarse ~500m grid cell."""
    snapped_lat = round(round(lat / step) * step, 4)
    snapped_lng = round(round(lng / step) * step, 4)
    return snapped_lat, snapped_lng


def aggregate_hotspots(incidents: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Aggregate incidents into privacy-safe, k-anonymized hotspot cells."""
    buckets: dict[tuple[float, float, str], int] = defaultdict(int)

    for inc in incidents:
        lat = inc.get("lat")
        lng = inc.get("lng")
        if lat is None or lng is None:
            continue
        category = inc.get("category", "PERSONAL_SAFETY")
        grid_lat, grid_lng = coarsen_coord(float(lat), float(lng))
        buckets[(grid_lat, grid_lng, category)] += 1

    results: list[dict[str, Any]] = []
    for (grid_lat, grid_lng, category), count in buckets.items():
        is_gbv = category.startswith("GBV_") or category == "GBV_DOMESTIC"
        threshold = MIN_THRESHOLD_GBV if is_gbv else MIN_THRESHOLD_PUBLIC

        if count < threshold:
            # Suppress cells below k-anonymity threshold to prevent re-identification
            continue

        density = "HIGH" if count >= 20 else "MEDIUM" if count >= 10 else "LOW"

        results.append({
            "grid_lat": grid_lat,
            "grid_lng": grid_lng,
            "cell_size_meters": 500,
            "category": category,
            "incident_count": count,
            "density_level": density,
            "privacy_notice": "Coarsened to 500m; cells < 5 events suppressed",
        })

    # Sort descending by count
    return sorted(results, key=lambda x: x["incident_count"], reverse=True)
