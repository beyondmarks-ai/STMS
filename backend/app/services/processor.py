import hashlib
from datetime import timedelta
from functools import lru_cache
from pathlib import Path

from ..models import Incident, JobStatus, ProcessingJob, ViolationType
from ..store import Store
from ..config import get_settings
from .video_analyzer import VideoAnalyzer
from .azure_enrichment import AzureFaceCropper, AzureOpenAIVisionEnricher


class DemoVideoProcessor:
    """Deterministic contract adapter used until an Azure ML endpoint is configured.

    It intentionally does not claim to analyse pixels. It creates stable sample
    incidents so the upload/review/audit workflow can be exercised end to end.
    """

    def process(self, job: ProcessingJob, video_path: Path, store: Store) -> ProcessingJob:
        digest = hashlib.sha256(video_path.read_bytes()[:1_000_000]).hexdigest()
        templates = [
            (ViolationType.no_helmet, .91, "Rider persisted without an associated helmet for 2.6 seconds."),
            (ViolationType.triple_riding, .87, "Three riders persisted on one motorcycle track."),
            (ViolationType.wrong_side, .84, "Vehicle movement opposed the configured legal direction."),
            (ViolationType.ambulance_obstruction, .81, "Vehicle persisted in the configured ambulance clearance corridor."),
        ]
        count = 1 + int(digest[0], 16) % 2
        for index in range(count):
            kind, confidence, explanation = templates[int(digest[index + 1], 16) % len(templates)]
            store.save_incident(Incident(
                type=kind,
                camera=job.camera,
                confidence=confidence,
                plate=f"KA 0{index + 1} MX {int(digest[4:8], 16) % 10000:04d}",
                detected_at=job.created_at + timedelta(seconds=8 + index * 11),
                explanation=f"Demo adapter: {explanation}",
                job_id=job.id,
            ))
        completed = job.model_copy(update={"status": JobStatus.completed, "progress": 1, "incident_count": count})
        return store.save_job(completed)


class RealVideoProcessor:
    """Frame-by-frame CPU analyzer; Azure ML can host the same model contract."""

    def process(self, job: ProcessingJob, video_path: Path, store: Store) -> ProcessingJob:
        def report(value: float) -> None:
            store.save_job(job.model_copy(update={"status": JobStatus.processing, "progress": value}))

        incidents = get_video_analyzer().analyze(job, video_path, report)
        for incident in incidents:
            store.save_incident(incident)
        completed = job.model_copy(update={
            "status": JobStatus.completed,
            "progress": 1,
            "incident_count": len(incidents),
        })
        return store.save_job(completed)


@lru_cache(maxsize=1)
def get_video_analyzer() -> VideoAnalyzer:
    settings = get_settings()
    return VideoAnalyzer(
        model_dir=settings.model_dir,
        evidence_root=settings.evidence_dir,
        confidence=settings.detection_confidence,
        inference_fps=settings.inference_fps,
        max_sampled_frames=settings.max_sampled_frames,
        automatic_direction_detection=settings.automatic_direction_detection,
        azure_enricher=AzureOpenAIVisionEnricher(
            settings.azure_openai_endpoint,
            settings.azure_openai_api_key,
            settings.azure_openai_deployment,
        ),
        azure_face_cropper=AzureFaceCropper(
            settings.azure_face_endpoint,
            settings.azure_face_api_key,
        ),
    )
