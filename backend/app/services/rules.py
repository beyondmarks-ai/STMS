import re
from dataclasses import dataclass
from math import hypot


INDIAN_PLATE_PATTERN = re.compile(
    r"^(?:[A-Z]{2})(?:0[1-9]|[1-9][0-9])(?:[A-Z]{1,3})(?:[0-9]{4})$"
)


def normalize_indian_plate(raw_text: str) -> str | None:
    """Normalize OCR output while refusing implausible registration strings."""
    compact = re.sub(r"[^A-Z0-9]", "", raw_text.upper())
    if len(compact) < 9 or len(compact) > 11:
        return None
    # OCR commonly confuses O/0 in the district and serial sections.
    prefix = compact[:2].replace("0", "O")
    district = compact[2:4].replace("O", "0").replace("I", "1")
    series = compact[4:-4].replace("0", "O")
    serial = compact[-4:].replace("O", "0").replace("I", "1")
    candidate = f"{prefix}{district}{series}{serial}"
    if not INDIAN_PLATE_PATTERN.fullmatch(candidate):
        return None
    return f"{prefix} {district} {series} {serial}"


@dataclass(frozen=True)
class TrackSample:
    timestamp_seconds: float
    center_x: float
    center_y: float
    helmet_count: int = 0
    rider_count: int = 0
    in_ambulance_corridor: bool = False
    speed_pixels_per_second: float = 0


@dataclass(frozen=True)
class CameraRules:
    allowed_direction_x: float = 0
    allowed_direction_y: float = 1
    persistence_seconds: float = 2.5
    obstruction_seconds: float = 5
    stopped_speed_threshold: float = 4


class TemporalRuleEngine:
    """Explainable rules over model detections associated into one vehicle track."""

    def evaluate(self, samples: list[TrackSample], rules: CameraRules) -> set[str]:
        if len(samples) < 2:
            return set()
        ordered = sorted(samples, key=lambda sample: sample.timestamp_seconds)
        duration = ordered[-1].timestamp_seconds - ordered[0].timestamp_seconds
        findings: set[str] = set()
        if duration >= rules.persistence_seconds:
            if all(sample.rider_count > 0 and sample.helmet_count < sample.rider_count for sample in ordered):
                findings.add("noHelmet")
            if all(sample.rider_count >= 3 for sample in ordered):
                findings.add("tripleRiding")
            dx = ordered[-1].center_x - ordered[0].center_x
            dy = ordered[-1].center_y - ordered[0].center_y
            movement = hypot(dx, dy)
            if movement > 10 and dx * rules.allowed_direction_x + dy * rules.allowed_direction_y < 0:
                findings.add("wrongSide")
        if duration >= rules.obstruction_seconds and all(
            sample.in_ambulance_corridor
            and sample.speed_pixels_per_second <= rules.stopped_speed_threshold
            for sample in ordered
        ):
            findings.add("ambulanceObstruction")
        return findings
