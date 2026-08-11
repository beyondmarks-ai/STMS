from datetime import datetime, timezone
from enum import Enum
from uuid import uuid4

from pydantic import BaseModel, ConfigDict, Field


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class CamelModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


class ViolationType(str, Enum):
    no_helmet = "noHelmet"
    triple_riding = "tripleRiding"
    wrong_side = "wrongSide"
    ambulance_obstruction = "ambulanceObstruction"


class ReviewStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    needs_review = "needsReview"


class PenaltyStatus(str, Enum):
    pending = "pending"
    confirmed = "confirmed"
    void = "void"


class JobStatus(str, Enum):
    queued = "queued"
    processing = "processing"
    completed = "completed"
    failed = "failed"


class Incident(CamelModel):
    id: str = Field(default_factory=lambda: f"INC-{uuid4().hex[:8].upper()}")
    type: ViolationType
    status: ReviewStatus = ReviewStatus.pending
    plate: str = "Unreadable"
    camera: str
    confidence: float = Field(ge=0, le=1)
    detected_at: datetime = Field(default_factory=utc_now, alias="detectedAt")
    explanation: str
    evidence_url: str = Field(default="", alias="evidenceUrl")
    plate_crop_url: str | None = Field(default=None, alias="plateCropUrl")
    face_crop_url: str | None = Field(default=None, alias="faceCropUrl")
    rider_count: int | None = Field(default=None, alias='riderCount', ge=0, le=6)
    vehicle_type: str | None = Field(default=None, alias='vehicleType')
    vehicle_body_style: str | None = Field(default=None, alias='vehicleBodyStyle')
    vehicle_color: str | None = Field(default=None, alias='vehicleColor')
    vehicle_make: str | None = Field(default=None, alias='vehicleMake')
    vehicle_model: str | None = Field(default=None, alias='vehicleModel')
    azure_description: str | None = Field(default=None, alias='azureDescription')
    enrichment_confidence: float | None = Field(
        default=None, alias='enrichmentConfidence', ge=0, le=1
    )
    enrichment_uncertainties: list[str] = Field(
        default_factory=list, alias='enrichmentUncertainties'
    )
    note: str | None = None
    job_id: str = Field(alias="jobId")
    model_version: str = Field(default="demo-1.0", alias="modelVersion")
    calibration_version: str = Field(default="default-1", alias="calibrationVersion")


class ProcessingJob(CamelModel):
    id: str = Field(default_factory=lambda: f"JOB-{uuid4().hex[:8].upper()}")
    file_name: str = Field(alias="fileName")
    camera: str
    status: JobStatus = JobStatus.queued
    progress: float = Field(default=0, ge=0, le=1)
    created_at: datetime = Field(default_factory=utc_now, alias="createdAt")
    incident_count: int = Field(default=0, alias="incidentCount")
    error: str | None = None
    source_blob: str | None = Field(default=None, alias="sourceBlob")


class ReviewRequest(CamelModel):
    status: ReviewStatus
    note: str = Field(default="", max_length=1000)


class Penalty(CamelModel):
    id: str
    incident_id: str = Field(alias="incidentId")
    plate: str
    violation_type: ViolationType = Field(alias="violationType")
    violation_label: str = Field(alias="violationLabel")
    amount: int = Field(gt=0)
    currency: str = "INR"
    status: PenaltyStatus = PenaltyStatus.pending
    camera: str
    detected_at: datetime = Field(alias="detectedAt")
    created_at: datetime = Field(default_factory=utc_now, alias="createdAt")
    updated_at: datetime = Field(default_factory=utc_now, alias="updatedAt")
    review_note: str | None = Field(default=None, alias="reviewNote")


class VehiclePenaltySummary(CamelModel):
    plate: str
    penalty_count: int = Field(alias="penaltyCount")
    pending_count: int = Field(alias="pendingCount")
    confirmed_count: int = Field(alias="confirmedCount")
    total_amount: int = Field(alias="totalAmount")
    confirmed_amount: int = Field(alias="confirmedAmount")
    currency: str = "INR"
    last_detected_at: datetime = Field(alias="lastDetectedAt")


class PenaltyTariff(CamelModel):
    violation_type: ViolationType = Field(alias="violationType")
    label: str
    amount: int = Field(gt=0)
    currency: str = "INR"


class HealthResponse(CamelModel):
    status: str
    environment: str
    processor: str
