from __future__ import annotations

import ast
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort


@dataclass(frozen=True)
class Detection:
    label: str
    confidence: float
    box: tuple[int, int, int, int]

    @property
    def center(self) -> tuple[float, float]:
        x1, y1, x2, y2 = self.box
        return ((x1 + x2) / 2, (y1 + y2) / 2)


class OnnxYoloDetector:
    """Small ONNX Runtime wrapper for raw and end-to-end Ultralytics exports."""

    def __init__(self, model_path: Path, confidence: float = .3, iou: float = .5) -> None:
        if not model_path.exists():
            raise FileNotFoundError(
                f"Missing model {model_path}. Run: python tools/download_models.py"
            )
        options = ort.SessionOptions()
        options.intra_op_num_threads = max(1, min(4, __import__("os").cpu_count() or 1))
        self.session = ort.InferenceSession(
            str(model_path), options, providers=["CPUExecutionProvider"]
        )
        self.input = self.session.get_inputs()[0]
        self.input_height = int(self.input.shape[2])
        self.input_width = int(self.input.shape[3])
        self.confidence = confidence
        self.iou = iou
        metadata = self.session.get_modelmeta().custom_metadata_map
        raw_names = metadata.get("names", "{}")
        try:
            parsed = ast.literal_eval(raw_names)
            self.names = {int(key): str(value) for key, value in parsed.items()}
        except (SyntaxError, ValueError, AttributeError):
            self.names = {}

    def predict(self, frame: np.ndarray, labels: set[str] | None = None) -> list[Detection]:
        tensor, ratio, pad_x, pad_y = self._letterbox(frame)
        output = self.session.run(None, {self.input.name: tensor})[0]
        rows = np.squeeze(output)
        if rows.ndim != 2:
            return []
        # End-to-end exports return [N, x1, y1, x2, y2, confidence, class].
        if rows.shape[1] == 6:
            return self._from_end_to_end(rows, frame.shape, ratio, pad_x, pad_y, labels)
        if rows.shape[0] < rows.shape[1]:
            rows = rows.T
        return self._from_raw(rows, frame.shape, ratio, pad_x, pad_y, labels)

    def _letterbox(self, frame: np.ndarray) -> tuple[np.ndarray, float, float, float]:
        height, width = frame.shape[:2]
        ratio = min(self.input_width / width, self.input_height / height)
        resized_width, resized_height = int(round(width * ratio)), int(round(height * ratio))
        resized = cv2.resize(frame, (resized_width, resized_height), interpolation=cv2.INTER_LINEAR)
        canvas = np.full((self.input_height, self.input_width, 3), 114, dtype=np.uint8)
        pad_x = (self.input_width - resized_width) / 2
        pad_y = (self.input_height - resized_height) / 2
        left, top = int(round(pad_x - .1)), int(round(pad_y - .1))
        canvas[top:top + resized_height, left:left + resized_width] = resized
        tensor = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        tensor = np.transpose(tensor, (2, 0, 1))[None]
        return np.ascontiguousarray(tensor), ratio, pad_x, pad_y

    def _from_raw(
        self,
        rows: np.ndarray,
        frame_shape: tuple[int, ...],
        ratio: float,
        pad_x: float,
        pad_y: float,
        labels: set[str] | None,
    ) -> list[Detection]:
        boxes: list[list[int]] = []
        scores: list[float] = []
        class_ids: list[int] = []
        for row in rows:
            class_scores = row[4:]
            class_id = int(np.argmax(class_scores))
            score = float(class_scores[class_id])
            label = self.names.get(class_id, str(class_id))
            if score < self.confidence or (labels is not None and label not in labels):
                continue
            cx, cy, width, height = map(float, row[:4])
            x = int((cx - width / 2 - pad_x) / ratio)
            y = int((cy - height / 2 - pad_y) / ratio)
            boxes.append([x, y, int(width / ratio), int(height / ratio)])
            scores.append(score)
            class_ids.append(class_id)
        # Suppress duplicates within each class. A rider and motorcycle can
        # overlap heavily; cross-class NMS would discard one of them.
        selected: list[int] = []
        for class_id in sorted(set(class_ids)):
            indices = [i for i, value in enumerate(class_ids) if value == class_id]
            kept = cv2.dnn.NMSBoxes(
                [boxes[i] for i in indices],
                [scores[i] for i in indices],
                self.confidence,
                self.iou,
            )
            selected.extend(indices[int(i)] for i in np.array(kept).reshape(-1))
        selected.sort(key=lambda i: scores[i], reverse=True)
        return [
            Detection(
                self.names.get(class_ids[int(index)], str(class_ids[int(index)])),
                scores[int(index)],
                self._clip_xywh(boxes[int(index)], frame_shape),
            )
            for index in np.array(selected).reshape(-1)
        ] if len(selected) else []

    def _from_end_to_end(
        self,
        rows: np.ndarray,
        frame_shape: tuple[int, ...],
        ratio: float,
        pad_x: float,
        pad_y: float,
        labels: set[str] | None,
    ) -> list[Detection]:
        detections: list[Detection] = []
        for row in rows:
            score = float(row[4])
            class_id = int(row[5])
            label = self.names.get(class_id, str(class_id))
            if score < self.confidence or (labels is not None and label not in labels):
                continue
            x1 = int((float(row[0]) - pad_x) / ratio)
            y1 = int((float(row[1]) - pad_y) / ratio)
            x2 = int((float(row[2]) - pad_x) / ratio)
            y2 = int((float(row[3]) - pad_y) / ratio)
            detections.append(Detection(label, score, self._clip_xyxy((x1, y1, x2, y2), frame_shape)))
        return detections

    @staticmethod
    def _clip_xywh(box: list[int], shape: tuple[int, ...]) -> tuple[int, int, int, int]:
        x, y, width, height = box
        return OnnxYoloDetector._clip_xyxy((x, y, x + width, y + height), shape)

    @staticmethod
    def _clip_xyxy(box: tuple[int, int, int, int], shape: tuple[int, ...]) -> tuple[int, int, int, int]:
        height, width = shape[:2]
        x1, y1, x2, y2 = box
        return max(0, x1), max(0, y1), min(width - 1, x2), min(height - 1, y2)


def intersection_over_union(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    x1, y1 = max(a[0], b[0]), max(a[1], b[1])
    x2, y2 = min(a[2], b[2]), min(a[3], b[3])
    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    area_a = max(0, a[2] - a[0]) * max(0, a[3] - a[1])
    area_b = max(0, b[2] - b[0]) * max(0, b[3] - b[1])
    union = area_a + area_b - intersection
    return intersection / union if union else 0
