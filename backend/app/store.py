from threading import RLock

from .models import Incident, ProcessingJob, ReviewRequest


class MemoryStore:
    """Development store; CosmosStore implements the same boundary in Azure."""

    def __init__(self) -> None:
        self._jobs: dict[str, ProcessingJob] = {}
        self._incidents: dict[str, Incident] = {}
        self._lock = RLock()

    def list_jobs(self) -> list[ProcessingJob]:
        with self._lock:
            return sorted(self._jobs.values(), key=lambda item: item.created_at, reverse=True)

    def save_job(self, job: ProcessingJob) -> ProcessingJob:
        with self._lock:
            self._jobs[job.id] = job
            return job

    def get_job(self, job_id: str) -> ProcessingJob | None:
        return self._jobs.get(job_id)

    def list_incidents(self) -> list[Incident]:
        with self._lock:
            return sorted(self._incidents.values(), key=lambda item: item.detected_at, reverse=True)

    def save_incident(self, incident: Incident) -> Incident:
        with self._lock:
            self._incidents[incident.id] = incident
            return incident

    def review_incident(self, incident_id: str, review: ReviewRequest) -> Incident | None:
        with self._lock:
            incident = self._incidents.get(incident_id)
            if incident is None:
                return None
            updated = incident.model_copy(update={"status": review.status, "note": review.note})
            self._incidents[incident_id] = updated
            return updated


store = MemoryStore()
