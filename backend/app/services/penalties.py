from ..models import (
    Incident,
    Penalty,
    PenaltyStatus,
    PenaltyTariff,
    ReviewStatus,
    ViolationType,
    utc_now,
)
from .rules import normalize_indian_plate


# Pilot tariff schedule. Keep this centralized so deployments can revise it
# without changing OCR or incident processing logic.
PENALTY_SCHEDULE: dict[ViolationType, tuple[str, int]] = {
    ViolationType.no_helmet: ("Riding without a helmet", 1000),
    ViolationType.triple_riding: ("More than two riders", 1000),
    ViolationType.wrong_side: ("Driving on the wrong side", 500),
    ViolationType.ambulance_obstruction: ("Failure to give way to an ambulance", 10000),
}


def penalty_status(review_status: ReviewStatus) -> PenaltyStatus:
    if review_status == ReviewStatus.approved:
        return PenaltyStatus.confirmed
    if review_status == ReviewStatus.rejected:
        return PenaltyStatus.void
    return PenaltyStatus.pending


def build_penalty(incident: Incident, existing: Penalty | None = None) -> Penalty | None:
    """Create or synchronize an incident penalty only when OCR is valid."""
    plate = normalize_indian_plate(incident.plate)
    if plate is None:
        return None
    label, amount = PENALTY_SCHEDULE[incident.type]
    now = utc_now()
    return Penalty(
        id=f"PEN-{incident.id}",
        incidentId=incident.id,
        plate=plate,
        violationType=incident.type,
        violationLabel=label,
        amount=amount,
        status=penalty_status(incident.status),
        camera=incident.camera,
        detectedAt=incident.detected_at,
        createdAt=existing.created_at if existing else now,
        updatedAt=now,
        reviewNote=incident.note,
    )


def tariffs() -> list[PenaltyTariff]:
    return [
        PenaltyTariff(violationType=kind, label=label, amount=amount)
        for kind, (label, amount) in PENALTY_SCHEDULE.items()
    ]
