import numpy as np

from app.services.onnx_detector import OnnxYoloDetector


def test_nms_preserves_overlapping_rider_and_motorcycle_but_removes_duplicates():
    detector = OnnxYoloDetector.__new__(OnnxYoloDetector)
    detector.names = {0: "person", 1: "motorcycle"}
    detector.confidence = .3
    detector.iou = .5
    rows = np.array([
        [100, 100, 100, 100, .95, .01],
        [102, 102, 100, 100, .01, .90],
        [103, 103, 100, 100, .01, .70],
    ])

    detections = detector._from_raw(rows, (300, 300, 3), 1, 0, 0, None)

    assert [item.label for item in detections] == ["person", "motorcycle"]
    assert [item.confidence for item in detections] == [.95, .90]


def test_nms_keeps_separate_motorcycles_and_respects_label_filter():
    detector = OnnxYoloDetector.__new__(OnnxYoloDetector)
    detector.names = {0: "person", 1: "motorcycle"}
    detector.confidence = .3
    detector.iou = .5
    rows = np.array([
        [100, 100, 50, 50, .95, .01],
        [100, 100, 50, 50, .01, .90],
        [200, 200, 50, 50, .01, .80],
        [250, 250, 50, 50, .01, .20],
    ])

    detections = detector._from_raw(
        rows, (300, 300, 3), 1, 0, 0, {"motorcycle"}
    )

    assert [item.label for item in detections] == ["motorcycle", "motorcycle"]
    assert len(detector._from_raw(rows, (300, 300, 3), 1, 0, 0, set())) == 0
