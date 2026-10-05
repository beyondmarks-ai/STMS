from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from statistics import median
from typing import Callable

import cv2
import numpy as np
from rapidocr_onnxruntime import RapidOCR

from ..models import Incident, PlateStatus, ProcessingJob, ViolationType
from .azure_enrichment import (
    AzureFaceCropper,
    AzureOpenAIVisionEnricher,
    VehicleEnrichment,
)
from .onnx_detector import Detection, OnnxYoloDetector, intersection_over_union
from .rules import normalize_indian_plate


VEHICLE_LABELS = {"bicycle", "car", "motorcycle", "bus", "truck"}
RIDER_VEHICLES = {"motorcycle"}


@dataclass
class VehicleTrack:
    id: int
    label: str
    first_time: float
    last_time: float
    box: tuple[int, int, int, int]
    last_sample: int
    centers: list[tuple[float, float]] = field(default_factory=list)
    nohelmet_times: list[float] = field(default_factory=list)
    helmet_times: list[float] = field(default_factory=list)
    triple_times: list[float] = field(default_factory=list)
    max_riders: int = 0
    rider_counts: list[int] = field(default_factory=list)
    best_confidence: float = 0
    best_frame: np.ndarray | None = None
    best_box: tuple[int, int, int, int] | None = None
    plate_crop: np.ndarray | None = None
    plate_confidence: float = 0
    ocr_confidence: float = 0
    ocr_text: str = "Unreadable"
    scene_text: str = ""
    plate_read: bool = False
    enrichment: VehicleEnrichment | None = None
    enrichment_attempted: bool = False
    face_crop: np.ndarray | None = None

    @property
    def duration(self) -> float:
        return self.last_time - self.first_time

    @property
    def movement(self) -> tuple[float, float]:
        if len(self.centers) < 2:
            return 0, 0
        return self.centers[-1][0] - self.centers[0][0], self.centers[-1][1] - self.centers[0][1]


class VideoAnalyzer:
    def __init__(
        self,
        model_dir: Path,
        evidence_root: Path,
        confidence: float = .3,
        inference_fps: float = 2,
        max_sampled_frames: int = 1800,
        automatic_direction_detection: bool = False,
        azure_enricher: AzureOpenAIVisionEnricher | None = None,
        azure_face_cropper: AzureFaceCropper | None = None,
    ) -> None:
        self.model_dir = model_dir
        self.evidence_root = evidence_root
        self.inference_fps = max(.25, inference_fps)
        self.max_sampled_frames = max_sampled_frames
        self.automatic_direction_detection = automatic_direction_detection
        self.azure_enricher = azure_enricher
        self.azure_face_cropper = azure_face_cropper
        self.traffic = OnnxYoloDetector(model_dir / "traffic.onnx", confidence)
        self.helmet_plate = OnnxYoloDetector(model_dir / "helmet_plate.onnx", max(.25, confidence))
        self.plate = OnnxYoloDetector(model_dir / "plate.onnx", max(.25, confidence))
        self.ocr = RapidOCR()
        self.face = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")

    def analyze(
        self,
        job: ProcessingJob,
        video_path: Path,
        progress: Callable[[float], None] | None = None,
    ) -> list[Incident]:
        capture = cv2.VideoCapture(str(video_path))
        if not capture.isOpened():
            raise ValueError("The uploaded file is not a readable video.")
        source_fps = float(capture.get(cv2.CAP_PROP_FPS) or 0)
        total_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        if source_fps <= 0 or total_frames <= 0:
            capture.release()
            raise ValueError("Video metadata is invalid or its codec is unsupported.")
        stride = max(1, round(source_fps / self.inference_fps))
        expected_samples = min(self.max_sampled_frames, (total_frames + stride - 1) // stride)
        tracks: list[VehicleTrack] = []
        sample_index = 0
        frame_index = 0
        next_track_id = 1
        previous_gray: np.ndarray | None = None
        camera_shifts: list[float] = []
        try:
            while sample_index < self.max_sampled_frames:
                ok, frame = capture.read()
                if not ok:
                    break
                if frame_index % stride:
                    frame_index += 1
                    continue
                timestamp = frame_index / source_fps
                motion_gray = cv2.resize(
                    cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), (320, 180)
                ).astype(np.float32)
                if previous_gray is not None:
                    shift, response = cv2.phaseCorrelate(previous_gray, motion_gray)
                    if response >= .12:
                        camera_shifts.append(self._distance(shift))
                previous_gray = motion_gray
                detections = self.traffic.predict(frame, VEHICLE_LABELS | {"person"})
                vehicles = [item for item in detections if item.label in VEHICLE_LABELS]
                people = [item for item in detections if item.label == "person"]
                assignments, next_track_id = self._assign_tracks(
                    tracks, vehicles, sample_index, timestamp, next_track_id
                )
                rider_assignments = self._associate_people(assignments, people)
                for track, detection in assignments:
                    if detection.confidence >= track.best_confidence:
                        track.best_confidence = detection.confidence
                        track.best_frame = frame.copy()
                        track.best_box = detection.box
                    if track.label in RIDER_VEHICLES:
                        self._inspect_riders(
                            track,
                            detection,
                            rider_assignments.get(track.id, []),
                            frame,
                            timestamp,
                        )
                sample_index += 1
                frame_index += 1
                if progress and (sample_index == 1 or sample_index % 5 == 0):
                    progress(min(.88, .08 + .80 * sample_index / max(1, expected_samples)))
        finally:
            capture.release()
        if not tracks:
            return []
        if progress:
            progress(.9)
        for track in tracks:
            if (
                track.label in {"car", "bus", "truck"}
                and len(track.centers) >= 3
                and track.best_box is not None
                and (track.best_box[2] - track.best_box[0]) * (track.best_box[3] - track.best_box[1]) >= 20_000
            ):
                self._read_scene_text(track)
        moving_camera = bool(camera_shifts and median(camera_shifts) > 2.5)
        allowed_direction = (
            self._infer_allowed_direction(tracks)
            if self.automatic_direction_detection and not moving_camera
            else None
        )
        incidents = self._build_incidents(job, tracks, allowed_direction)
        if progress:
            progress(.98)
        return incidents

    def _assign_tracks(
        self,
        tracks: list[VehicleTrack],
        detections: list[Detection],
        sample_index: int,
        timestamp: float,
        next_id: int,
    ) -> tuple[list[tuple[VehicleTrack, Detection]], int]:
        assignments: list[tuple[VehicleTrack, Detection]] = []
        used: set[int] = set()
        for detection in sorted(detections, key=lambda item: item.confidence, reverse=True):
            candidates = [
                track for track in tracks
                if track.label == detection.label and track.id not in used and sample_index - track.last_sample <= 4
            ]
            track = max(candidates, key=lambda item: intersection_over_union(item.box, detection.box), default=None)
            if track is None or intersection_over_union(track.box, detection.box) < .18:
                track = VehicleTrack(
                    id=next_id,
                    label=detection.label,
                    first_time=timestamp,
                    last_time=timestamp,
                    box=detection.box,
                    last_sample=sample_index,
                )
                tracks.append(track)
                next_id += 1
            track.box = detection.box
            track.last_time = timestamp
            track.last_sample = sample_index
            track.centers.append(detection.center)
            used.add(track.id)
            assignments.append((track, detection))
        return assignments, next_id

    @classmethod
    def _associate_people(
        cls,
        assignments: list[tuple[VehicleTrack, Detection]],
        people: list[Detection],
    ) -> dict[int, list[Detection]]:
        rider_vehicles = [
            (track, vehicle)
            for track, vehicle in assignments
            if track.label in RIDER_VEHICLES
        ]
        result: dict[int, list[Detection]] = {
            track.id: [] for track, _ in rider_vehicles
        }
        # A person may be assigned to at most one vehicle in a sampled frame.
        for person in people:
            scored = [
                (cls._rider_match_score(person, vehicle), track.id)
                for track, vehicle in rider_vehicles
            ]
            score, track_id = max(scored, default=(0.0, -1))
            if score >= .42:
                result[track_id].append(person)
        return result

    @staticmethod
    def _rider_match_score(person: Detection, vehicle: Detection) -> float:
        px1, py1, px2, py2 = person.box
        vx1, vy1, vx2, vy2 = vehicle.box
        vehicle_width = max(1, vx2 - vx1)
        vehicle_height = max(1, vy2 - vy1)
        person_width = max(1, px2 - px1)
        foot_x = (px1 + px2) / 2
        horizontal_overlap = max(0, min(px2, vx2) - max(px1, vx1))
        overlap_ratio = horizontal_overlap / min(person_width, vehicle_width)
        horizontally_near = vx1 - .12 * vehicle_width <= foot_x <= vx2 + .12 * vehicle_width
        feet_near_vehicle = vy1 - .45 * vehicle_height <= py2 <= vy2 + .22 * vehicle_height
        if not horizontally_near or not feet_near_vehicle or overlap_ratio < .18:
            return 0.0
        vehicle_center_x = (vx1 + vx2) / 2
        distance_score = max(
            0.0, 1 - abs(foot_x - vehicle_center_x) / (vehicle_width * .75)
        )
        return .65 * min(1.0, overlap_ratio) + .35 * distance_score

    def _inspect_riders(
        self,
        track: VehicleTrack,
        vehicle: Detection,
        riders: list[Detection],
        frame: np.ndarray,
        timestamp: float,
    ) -> None:
        x1, y1, x2, y2 = vehicle.box
        width, height = x2 - x1, y2 - y1
        association = (
            max(0, int(x1 - .35 * width)),
            max(0, int(y1 - 1.15 * height)),
            min(frame.shape[1] - 1, int(x2 + .35 * width)),
            min(frame.shape[0] - 1, int(y2 + .1 * height)),
        )
        rider_count = len(riders)
        track.rider_counts.append(rider_count)
        track.max_riders = max(track.max_riders, rider_count)
        if rider_count >= 3:
            track.triple_times.append(timestamp)
        ax1, ay1, ax2, ay2 = association
        crop = frame[ay1:ay2, ax1:ax2]
        if crop.size == 0:
            return
        specialized = self.helmet_plate.predict(crop, {"helmet", "nohelmet", "licenseplate"})
        saw_nohelmet = False
        saw_helmet = False
        for item in specialized:
            if item.label == "nohelmet":
                saw_nohelmet = True
            elif item.label == "helmet":
                saw_helmet = True
            elif item.label == "licenseplate" and item.confidence > track.plate_confidence:
                px1, py1, px2, py2 = item.box
                plate_crop = crop[py1:py2, px1:px2]
                if plate_crop.size:
                    track.plate_crop = plate_crop.copy()
                    track.plate_confidence = item.confidence
        if saw_nohelmet:
            track.nohelmet_times.append(timestamp)
        if saw_helmet:
            track.helmet_times.append(timestamp)

    def _read_plate_and_scene(self, track: VehicleTrack) -> None:
        if track.plate_read:
            return
        track.plate_read = True
        if track.best_frame is None:
            return
        x1, y1, x2, y2 = track.best_box or track.box
        vehicle_crop = track.best_frame[y1:y2, x1:x2]
        if vehicle_crop.size == 0:
            return
        if track.plate_crop is None:
            candidates = self.plate.predict(vehicle_crop, {"license_plate"})
            if candidates:
                best = max(candidates, key=lambda item: item.confidence)
                px1, py1, px2, py2 = best.box
                plate_crop = vehicle_crop[py1:py2, px1:px2]
                if plate_crop.size:
                    track.plate_crop = plate_crop.copy()
                    track.plate_confidence = best.confidence
        if track.plate_crop is not None:
            track.ocr_text, track.ocr_confidence = self._ocr_plate(track.plate_crop)
        if track.label in {"car", "bus", "truck"} and not track.scene_text:
            track.scene_text = " ".join(self._ocr_strings(vehicle_crop)).upper()

    def _read_scene_text(self, track: VehicleTrack) -> None:
        if track.scene_text or track.best_frame is None:
            return
        x1, y1, x2, y2 = track.best_box or track.box
        crop = track.best_frame[y1:y2, x1:x2]
        if crop.size:
            track.scene_text = " ".join(self._ocr_strings(crop)).upper()

    def _ocr_plate(self, crop: np.ndarray) -> tuple[str, float]:
        scaled = cv2.resize(crop, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
        gray = cv2.cvtColor(scaled, cv2.COLOR_BGR2GRAY)
        enhanced = cv2.createCLAHE(2.0, (8, 8)).apply(gray)
        candidates = self._ocr_results(enhanced)
        candidates.extend(self._ocr_results(scaled))
        valid = [(normalize_indian_plate(value), confidence) for value, confidence in candidates]
        valid = [(value, confidence) for value, confidence in valid if value]
        if valid:
            return valid[0][0], valid[0][1]
        raw = candidates[0][0].strip() if candidates else ""
        return (raw[:20] if raw else "Unreadable"), (candidates[0][1] if candidates else 0)

    def _ocr_results(self, image: np.ndarray) -> list[tuple[str, float]]:
        try:
            result, _ = self.ocr(image)
            if not result:
                return []
            return [(str(item[1]), float(item[2])) for item in result if len(item) >= 3 and float(item[2]) >= .05]
        except (RuntimeError, ValueError, cv2.error):
            return []

    def _ocr_strings(self, image: np.ndarray) -> list[str]:
        try:
            result, _ = self.ocr(image)
            if not result:
                return []
            return [str(item[1]) for item in result if len(item) >= 3 and float(item[2]) >= .35]
        except (RuntimeError, ValueError, cv2.error):
            return []

    def _infer_allowed_direction(self, tracks: list[VehicleTrack]) -> tuple[float, float]:
        movements = [track.movement for track in tracks if self._distance(track.movement) >= 20]
        if not movements:
            return 0, 1
        dx, dy = median(item[0] for item in movements), median(item[1] for item in movements)
        length = max(1, self._distance((dx, dy)))
        return dx / length, dy / length

    def _build_incidents(
        self,
        job: ProcessingJob,
        tracks: list[VehicleTrack],
        allowed_direction: tuple[float, float] | None,
    ) -> list[Incident]:
        incidents: list[Incident] = []
        for track in tracks:
            findings: list[tuple[ViolationType, float, str]] = []
            observed_counts = [count for count in track.rider_counts if count > 0]
            confirmed_riders = (
                int(round(median(observed_counts))) if observed_counts else 0
            )
            track.max_riders = confirmed_riders
            if track.label in RIDER_VEHICLES and len(track.nohelmet_times) >= 2:
                findings.append((ViolationType.no_helmet, min(.97, .70 + .04 * len(track.nohelmet_times)), f"No-helmet detections persisted across {len(track.nohelmet_times)} sampled frames."))
            if (
                track.label in RIDER_VEHICLES
                and confirmed_riders >= 3
                and len(track.triple_times) >= 2
            ):
                findings.append((ViolationType.triple_riding, min(.96, .74 + .04 * len(track.triple_times)), f"{track.max_riders} riders remained associated with one {track.label}."))
            if track.plate_crop is not None and track.ocr_confidence < .75:
                findings.append((ViolationType.tampered_plate, .82, f"Number plate OCR confidence was {track.ocr_confidence:.0%}, below the 75% safety threshold; possible occlusion or tampering."))
            movement = track.movement
            if allowed_direction is not None:
                dot = movement[0] * allowed_direction[0] + movement[1] * allowed_direction[1]
                if len(track.centers) >= 4 and track.duration >= 1.5 and self._distance(movement) >= 35 and dot < -25:
                    findings.append((ViolationType.wrong_side, min(.93, .72 + abs(dot) / 500), "Vehicle movement opposed the dominant direction in fixed-camera footage."))
            if findings and track.label in RIDER_VEHICLES:
                self._enrich_track(track)
                enrichment = track.enrichment
                if enrichment is not None and (enrichment.confidence or 0) >= .7:
                    azure_type = (enrichment.vehicle_type or '').lower()
                    if 'bicycle' in azure_type or azure_type == 'cycle':
                        findings = [
                            finding
                            for finding in findings
                            if finding[0]
                            not in {ViolationType.no_helmet, ViolationType.triple_riding}
                        ]
                    elif enrichment.rider_count is not None and enrichment.rider_count < 3:
                        findings = [
                            finding
                            for finding in findings
                            if finding[0] != ViolationType.triple_riding
                        ]
            for kind, confidence, explanation in findings:
                incidents.append(self._save_evidence(job, track, kind, confidence, explanation))
        if allowed_direction is not None:
            incidents.extend(self._ambulance_obstructions(job, tracks, allowed_direction))
        return incidents

    def _ambulance_obstructions(self, job: ProcessingJob, tracks: list[VehicleTrack], direction: tuple[float, float]) -> list[Incident]:
        ambulances = [track for track in tracks if "AMBULANCE" in track.scene_text.replace(" ", "")]
        incidents: list[Incident] = []
        for ambulance in ambulances:
            ax, ay = ambulance.centers[-1]
            width = max(30, ambulance.box[2] - ambulance.box[0])
            for blocker in tracks:
                if blocker.id == ambulance.id or not blocker.centers:
                    continue
                bx, by = blocker.centers[-1]
                forward = (bx - ax) * direction[0] + (by - ay) * direction[1]
                lateral = abs((bx - ax) * -direction[1] + (by - ay) * direction[0])
                if 0 < forward < width * 4 and lateral < width and self._distance(blocker.movement) < 25:
                    incidents.append(self._save_evidence(job, blocker, ViolationType.ambulance_obstruction, .78, "A mostly stationary vehicle occupied the detected ambulance's forward clearance corridor."))
        return incidents

    def _evidence_crop(self, track: VehicleTrack) -> np.ndarray | None:
        if track.best_frame is None:
            return None
        x1, y1, x2, y2 = track.best_box or track.box
        if track.label in RIDER_VEHICLES:
            width, height = x2 - x1, y2 - y1
            x1 = max(0, round(x1 - .2 * width))
            x2 = min(track.best_frame.shape[1], round(x2 + .2 * width))
            y1 = max(0, round(y1 - 1.25 * height))
            y2 = min(track.best_frame.shape[0], round(y2 + .1 * height))
        crop = track.best_frame[y1:y2, x1:x2]
        return crop.copy() if crop.size else None

    def _enrich_track(self, track: VehicleTrack) -> None:
        if track.enrichment_attempted:
            return
        track.enrichment_attempted = True
        crop = self._evidence_crop(track)
        if crop is None:
            return
        observed = [count for count in track.rider_counts if count > 0]
        local_count = int(round(median(observed))) if observed else None
        if self.azure_enricher is not None:
            track.enrichment = self.azure_enricher.enrich(crop, local_count)
        if self.azure_face_cropper is not None:
            track.face_crop = self.azure_face_cropper.crop_largest(crop)

    def _save_evidence(self, job: ProcessingJob, track: VehicleTrack, kind: ViolationType, confidence: float, explanation: str) -> Incident:
        self._read_plate_and_scene(track)
        self._enrich_track(track)
        enrichment = track.enrichment
        observed = [count for count in track.rider_counts if count > 0]
        rider_count = int(round(median(observed))) if observed else None
        incident = Incident(
            type=kind,
            camera=job.camera,
            confidence=confidence,
            plate=track.ocr_text,
            explanation=explanation,
            job_id=job.id,
            modelVersion="local-onnx-1.0",
            calibrationVersion=(
                "dominant-flow-1"
                if self.automatic_direction_detection
                else "uncalibrated-1"
            ),
        )
        normalized_plate = ''.join(c for c in track.ocr_text.upper() if c.isalnum())
        if not normalized_plate or normalized_plate in {'UNREADABLE', 'UNKNOWN'}:
            incident.plate_status = PlateStatus.unreadable
        elif track.ocr_confidence < .75 or len(normalized_plate) < 7 or len(set(normalized_plate)) <= 2:
            incident.plate_status = PlateStatus.obscured
        elif not any(c.isdigit() for c in normalized_plate) or not any(c.isalpha() for c in normalized_plate):
            incident.plate_status = PlateStatus.fake
        incident.rider_count = rider_count
        incident.vehicle_type = (
            enrichment.vehicle_type if enrichment else track.label
        )
        if enrichment is not None:
            incident.vehicle_body_style = enrichment.body_style
            incident.vehicle_color = enrichment.color
            incident.vehicle_make = enrichment.make
            incident.vehicle_model = enrichment.model
            incident.azure_description = enrichment.description
            incident.enrichment_confidence = enrichment.confidence
            incident.enrichment_uncertainties = list(enrichment.uncertainties)
            if (
                rider_count is not None
                and enrichment.rider_count is not None
                and rider_count != enrichment.rider_count
            ):
                incident.enrichment_uncertainties.append(
                    f'Azure estimated {enrichment.rider_count} riders while tracking estimated {rider_count}; human review required.'
                )
        folder = self.evidence_root / job.id / incident.id
        folder.mkdir(parents=True, exist_ok=True)
        frame = track.best_frame.copy() if track.best_frame is not None else np.zeros((480, 640, 3), dtype=np.uint8)
        x1, y1, x2, y2 = track.best_box or track.box
        cv2.rectangle(frame, (x1, y1), (x2, y2), (55, 244, 203), 3)
        cv2.putText(frame, kind.value, (x1, max(24, y1 - 8)), cv2.FONT_HERSHEY_SIMPLEX, .7, (55, 244, 203), 2, cv2.LINE_AA)
        cv2.imwrite(str(folder / "frame.jpg"), frame)
        vehicle_crop = self._evidence_crop(track)
        if vehicle_crop is not None and vehicle_crop.size:
            cv2.imwrite(str(folder / "vehicle.jpg"), vehicle_crop)
            face_crop = track.face_crop
            if face_crop is None:
                face_crop = self._find_face(vehicle_crop)
            if face_crop is not None:
                cv2.imwrite(str(folder / "face.jpg"), face_crop)
                incident.face_crop_url = f"/api/v1/evidence/{job.id}/{incident.id}/face.jpg"
        if track.plate_crop is not None:
            cv2.imwrite(str(folder / "plate.jpg"), track.plate_crop)
            incident.plate_crop_url = f"/api/v1/evidence/{job.id}/{incident.id}/plate.jpg"
        incident.evidence_url = f"/api/v1/evidence/{job.id}/{incident.id}/frame.jpg"
        incident.image_proof_url = incident.evidence_url
        return incident

    def _find_face(self, vehicle_crop: np.ndarray) -> np.ndarray | None:
        gray = cv2.cvtColor(vehicle_crop, cv2.COLOR_BGR2GRAY)
        faces = self.face.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(24, 24))
        if len(faces) == 0:
            return None
        x, y, width, height = max(faces, key=lambda item: item[2] * item[3])
        return vehicle_crop[y:y + height, x:x + width].copy()

    @staticmethod
    def _center_inside(detection: Detection, box: tuple[int, int, int, int]) -> bool:
        x, y = detection.center
        return box[0] <= x <= box[2] and box[1] <= y <= box[3]

    @staticmethod
    def _distance(vector: tuple[float, float]) -> float:
        return float(np.hypot(vector[0], vector[1]))
