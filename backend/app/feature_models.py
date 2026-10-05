from datetime import datetime
from uuid import uuid4

from pydantic import Field

from .models import CamelModel, utc_now


class VipVehicle(CamelModel):
    id: str = Field(default_factory=lambda: f"VIP-{uuid4().hex[:8].upper()}")
    plate: str = Field(min_length=4, max_length=16)
    owner: str = Field(min_length=2, max_length=80)
    reason: str = Field(min_length=2, max_length=200)
    active: bool = True
    expires_at: datetime | None = Field(default=None, alias="expiresAt")
    created_at: datetime = Field(default_factory=utc_now, alias="createdAt")


class Hotspot(CamelModel):
    camera: str
    violation_count: int = Field(alias="violationCount")
    risk_score: float = Field(alias="riskScore")
    top_violation: str = Field(alias="topViolation")
    last_detected_at: datetime = Field(alias="lastDetectedAt")


class NotificationPreviewRequest(CamelModel):
    incident_id: str = Field(alias="incidentId")
    channel: str = "whatsapp"
    recipient: str = Field(min_length=5, max_length=80)


class NotificationPreview(CamelModel):
    id: str = Field(default_factory=lambda: f"MSG-{uuid4().hex[:8].upper()}")
    incident_id: str = Field(alias="incidentId")
    channel: str
    recipient: str
    message: str
    image_proof_url: str = Field(alias="imageProofUrl")
    sandbox: bool = True
    status: str = "preview"
    created_at: datetime = Field(default_factory=utc_now, alias="createdAt")


class SandboxPaymentRequest(CamelModel):
    penalty_id: str = Field(alias="penaltyId")
    amount: int = Field(gt=0)


class SandboxPayment(CamelModel):
    id: str = Field(default_factory=lambda: f"UPI-TEST-{uuid4().hex[:8].upper()}")
    penalty_id: str = Field(alias="penaltyId")
    amount: int
    currency: str = "INR"
    provider: str = "UPI Sandbox"
    status: str = "success"
    sandbox: bool = True
    created_at: datetime = Field(default_factory=utc_now, alias="createdAt")
