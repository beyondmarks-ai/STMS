from threading import RLock
from typing import Protocol

from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

from .config import get_settings
from .models import (
    Incident,
    Penalty,
    PenaltyStatus,
    ProcessingJob,
    ReviewRequest,
    VehiclePenaltySummary,
)
from .services.penalties import build_penalty


class Store(Protocol):
    def list_jobs(self) -> list[ProcessingJob]: ...

    def save_job(self, job: ProcessingJob) -> ProcessingJob: ...

    def get_job(self, job_id: str) -> ProcessingJob | None: ...

    def list_incidents(self) -> list[Incident]: ...

    def save_incident(self, incident: Incident) -> Incident: ...

    def review_incident(
        self, incident_id: str, review: ReviewRequest
    ) -> Incident | None: ...

    def list_penalties(self) -> list[Penalty]: ...

    def list_vehicle_penalty_summaries(self) -> list[VehiclePenaltySummary]: ...


def _summarize_penalties(penalties: list[Penalty]) -> list[VehiclePenaltySummary]:
    grouped: dict[str, list[Penalty]] = {}
    for penalty in penalties:
        if penalty.status != PenaltyStatus.void:
            grouped.setdefault(penalty.plate, []).append(penalty)
    summaries = [
        VehiclePenaltySummary(
            plate=plate,
            penaltyCount=len(items),
            pendingCount=sum(item.status == PenaltyStatus.pending for item in items),
            confirmedCount=sum(
                item.status == PenaltyStatus.confirmed for item in items
            ),
            totalAmount=sum(item.amount for item in items),
            confirmedAmount=sum(
                item.amount
                for item in items
                if item.status == PenaltyStatus.confirmed
            ),
            lastDetectedAt=max(item.detected_at for item in items),
        )
        for plate, items in grouped.items()
    ]
    return sorted(summaries, key=lambda item: item.last_detected_at, reverse=True)


class MemoryStore:
    """Development store; CosmosStore implements the same boundary in Azure."""

    def __init__(self) -> None:
        self._jobs: dict[str, ProcessingJob] = {}
        self._incidents: dict[str, Incident] = {}
        self._penalties: dict[str, Penalty] = {}
        self._lock = RLock()

    def list_jobs(self) -> list[ProcessingJob]:
        with self._lock:
            return sorted(
                self._jobs.values(),
                key=lambda item: item.created_at,
                reverse=True,
            )

    def save_job(self, job: ProcessingJob) -> ProcessingJob:
        with self._lock:
            self._jobs[job.id] = job
            return job

    def get_job(self, job_id: str) -> ProcessingJob | None:
        return self._jobs.get(job_id)

    def list_incidents(self) -> list[Incident]:
        with self._lock:
            return sorted(
                self._incidents.values(),
                key=lambda item: item.detected_at,
                reverse=True,
            )

    def save_incident(self, incident: Incident) -> Incident:
        with self._lock:
            self._incidents[incident.id] = incident
            self._sync_penalty(incident)
            return incident

    def _sync_penalty(self, incident: Incident) -> None:
        penalty_id = f"PEN-{incident.id}"
        penalty = build_penalty(incident, self._penalties.get(penalty_id))
        if penalty is not None:
            self._penalties[penalty.id] = penalty

    def list_penalties(self) -> list[Penalty]:
        with self._lock:
            for incident in self._incidents.values():
                self._sync_penalty(incident)
            return sorted(
                self._penalties.values(),
                key=lambda item: item.detected_at,
                reverse=True,
            )

    def list_vehicle_penalty_summaries(self) -> list[VehiclePenaltySummary]:
        return _summarize_penalties(self.list_penalties())

    def review_incident(
        self, incident_id: str, review: ReviewRequest
    ) -> Incident | None:
        with self._lock:
            incident = self._incidents.get(incident_id)
            if incident is None:
                return None
            updated = incident.model_copy(
                update={'status': review.status, 'note': review.note}
            )
            self._incidents[incident_id] = updated
            self._sync_penalty(updated)
            return updated


class CosmosStore:
    """Persistent store authenticated with the Container App managed identity."""

    def __init__(self, endpoint: str, database: str) -> None:
        client = CosmosClient(endpoint, credential=DefaultAzureCredential())
        self._container = client.get_database_client(database).get_container_client(
            'operational'
        )

    def _query(
        self,
        query: str,
        parameters: list[dict[str, object]] | None = None,
    ) -> list[dict]:
        return list(
            self._container.query_items(
                query=query,
                parameters=parameters or [],
                enable_cross_partition_query=True,
            )
        )

    def list_jobs(self) -> list[ProcessingJob]:
        items = self._query("SELECT * FROM c WHERE c.documentType = 'job'")
        jobs = [ProcessingJob.model_validate(item) for item in items]
        return sorted(jobs, key=lambda item: item.created_at, reverse=True)

    def save_job(self, job: ProcessingJob) -> ProcessingJob:
        item = job.model_dump(by_alias=True, mode='json')
        item['documentType'] = 'job'
        self._container.upsert_item(item)
        return job

    def get_job(self, job_id: str) -> ProcessingJob | None:
        items = self._query(
            "SELECT * FROM c WHERE c.documentType = 'job' AND c.id = @id",
            [{'name': '@id', 'value': job_id}],
        )
        return ProcessingJob.model_validate(items[0]) if items else None

    def list_incidents(self) -> list[Incident]:
        items = self._query("SELECT * FROM c WHERE c.documentType = 'incident'")
        incidents = [Incident.model_validate(item) for item in items]
        return sorted(incidents, key=lambda item: item.detected_at, reverse=True)

    def save_incident(self, incident: Incident) -> Incident:
        item = incident.model_dump(by_alias=True, mode='json')
        item['documentType'] = 'incident'
        self._container.upsert_item(item)
        self._sync_penalty(incident)
        return incident

    def _penalty_for_incident(self, incident_id: str) -> Penalty | None:
        items = self._query(
            "SELECT * FROM c WHERE c.documentType = 'penalty' AND c.incidentId = @incidentId",
            [{'name': '@incidentId', 'value': incident_id}],
        )
        return Penalty.model_validate(items[0]) if items else None

    def _sync_penalty(self, incident: Incident) -> None:
        existing = self._penalty_for_incident(incident.id)
        penalty = build_penalty(incident, existing)
        if penalty is None:
            return
        item = penalty.model_dump(by_alias=True, mode='json')
        item['documentType'] = 'penalty'
        self._container.upsert_item(item)

    def list_penalties(self) -> list[Penalty]:
        # Backfill readable historical incidents once, while deterministic IDs
        # keep this operation idempotent.
        incidents = self.list_incidents()
        existing_items = self._query(
            "SELECT * FROM c WHERE c.documentType = 'penalty'"
        )
        existing = {
            item['incidentId']: Penalty.model_validate(item) for item in existing_items
        }
        for incident in incidents:
            if incident.id not in existing:
                self._sync_penalty(incident)
        if len(existing) != len(incidents):
            existing_items = self._query(
                "SELECT * FROM c WHERE c.documentType = 'penalty'"
            )
        penalties = [Penalty.model_validate(item) for item in existing_items]
        return sorted(penalties, key=lambda item: item.detected_at, reverse=True)

    def list_vehicle_penalty_summaries(self) -> list[VehiclePenaltySummary]:
        return _summarize_penalties(self.list_penalties())

    def review_incident(
        self, incident_id: str, review: ReviewRequest
    ) -> Incident | None:
        items = self._query(
            "SELECT * FROM c WHERE c.documentType = 'incident' AND c.id = @id",
            [{'name': '@id', 'value': incident_id}],
        )
        if not items:
            return None
        incident = Incident.model_validate(items[0])
        updated = incident.model_copy(
            update={'status': review.status, 'note': review.note}
        )
        return self.save_incident(updated)


def create_store() -> Store:
    settings = get_settings()
    if settings.cosmos_endpoint:
        return CosmosStore(settings.cosmos_endpoint, settings.cosmos_database)
    return MemoryStore()


store = create_store()
