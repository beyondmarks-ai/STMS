from app.services.azure_enrichment import AzureOpenAIVisionEnricher
from app.services.onnx_detector import Detection
from app.services.video_analyzer import VehicleTrack, VideoAnalyzer


def test_person_is_assigned_to_only_the_best_matching_motorcycle() -> None:
    first_track = VehicleTrack(1, "motorcycle", 0, 0, (100, 200, 220, 300), 0)
    second_track = VehicleTrack(2, "motorcycle", 0, 0, (260, 200, 380, 300), 0)
    first_vehicle = Detection("motorcycle", .9, first_track.box)
    second_vehicle = Detection("motorcycle", .9, second_track.box)
    rider = Detection("person", .9, (125, 90, 205, 280))
    nearby_pedestrian = Detection("person", .9, (390, 80, 470, 295))

    assignments = VideoAnalyzer._associate_people(
        [(first_track, first_vehicle), (second_track, second_vehicle)],
        [rider, nearby_pedestrian],
    )

    assert assignments[1] == [rider]
    assert assignments[2] == []


def test_azure_enrichment_rejects_unknown_and_invalid_values() -> None:
    result = AzureOpenAIVisionEnricher._from_json(
        {
            "riderCount": 1,
            "vehicleType": "scooter",
            "bodyStyle": "step-through",
            "color": "white",
            "make": "unknown",
            "model": None,
            "description": "One rider on a white scooter.",
            "confidence": 1.8,
            "uncertainties": ["Model badge is not visible."],
        }
    )

    assert result.rider_count == 1
    assert result.make is None
    assert result.model is None
    assert result.color == "white"
    assert result.confidence == 1
