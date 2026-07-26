from app.services.rules import CameraRules, TemporalRuleEngine, TrackSample, normalize_indian_plate


def test_normalizes_indian_plate_ocr_confusions() -> None:
    assert normalize_indian_plate("ka 01 mj 4821") == "KA 01 MJ 4821"
    assert normalize_indian_plate("KAO1MJ48O1") == "KA 01 MJ 4801"
    assert normalize_indian_plate("not a plate") is None


def test_temporal_rules_require_persistence() -> None:
    engine = TemporalRuleEngine()
    rules = CameraRules(allowed_direction_y=1, persistence_seconds=2)
    samples = [
        TrackSample(0, 100, 200, helmet_count=0, rider_count=3),
        TrackSample(1, 100, 180, helmet_count=0, rider_count=3),
        TrackSample(3, 100, 150, helmet_count=0, rider_count=3),
    ]
    assert engine.evaluate(samples, rules) == {"noHelmet", "tripleRiding", "wrongSide"}


def test_ambulance_obstruction_requires_corridor_and_low_speed() -> None:
    engine = TemporalRuleEngine()
    samples = [
        TrackSample(0, 10, 10, in_ambulance_corridor=True, speed_pixels_per_second=1),
        TrackSample(6, 11, 11, in_ambulance_corridor=True, speed_pixels_per_second=1),
    ]
    assert "ambulanceObstruction" in engine.evaluate(samples, CameraRules())
