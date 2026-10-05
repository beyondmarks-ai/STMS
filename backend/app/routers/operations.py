from collections import Counter, defaultdict

from fastapi import APIRouter, HTTPException, status

from ..feature_models import (
    Hotspot,
    NotificationPreview,
    NotificationPreviewRequest,
    SandboxPayment,
    SandboxPaymentRequest,
    VipVehicle,
)
from ..feature_store import feature_store
from ..store import store

router = APIRouter(prefix="/operations", tags=["operations"])


@router.get("/vip", response_model=list[VipVehicle], response_model_by_alias=True)
def list_vip() -> list[VipVehicle]:
    return feature_store.list_vip()


@router.post("/vip", response_model=VipVehicle, response_model_by_alias=True)
def add_vip(vehicle: VipVehicle) -> VipVehicle:
    vehicle.plate = "".join(c for c in vehicle.plate.upper() if c.isalnum())
    return feature_store.save_vip(vehicle)


@router.delete("/vip/{plate}")
def remove_vip(plate: str) -> dict[str, bool]:
    if not feature_store.delete_vip("".join(c for c in plate.upper() if c.isalnum())):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="VIP vehicle not found")
    return {"deleted": True}


@router.get("/hotspots", response_model=list[Hotspot], response_model_by_alias=True)
def hotspots() -> list[Hotspot]:
    grouped: dict[str, list] = defaultdict(list)
    for incident in store.list_incidents():
        grouped[incident.camera].append(incident)
    result = []
    for camera, incidents in grouped.items():
        types = Counter(item.type.value for item in incidents)
        result.append(Hotspot(camera=camera, violationCount=len(incidents), riskScore=min(100, round(len(incidents) * 12.5, 1)), topViolation=types.most_common(1)[0][0], lastDetectedAt=max(item.detected_at for item in incidents)))
    return sorted(result, key=lambda item: item.risk_score, reverse=True)


@router.post("/notifications/preview", response_model=NotificationPreview, response_model_by_alias=True)
def notification_preview(request: NotificationPreviewRequest) -> NotificationPreview:
    incident = next((item for item in store.list_incidents() if item.id == request.incident_id), None)
    if incident is None:
        raise HTTPException(status_code=404, detail="Incident not found")
    return NotificationPreview(incidentId=incident.id, channel=request.channel, recipient=request.recipient, message=f"STMS traffic notice: {incident.type.value} detected for {incident.plate}. Amount and proof require operator review.", imageProofUrl=incident.image_proof_url or incident.evidence_url)


@router.post("/payments/upi-sandbox", response_model=SandboxPayment, response_model_by_alias=True)
def sandbox_payment(request: SandboxPaymentRequest) -> SandboxPayment:
    penalty = next((item for item in store.list_penalties() if item.id == request.penalty_id), None)
    if penalty is None:
        raise HTTPException(status_code=404, detail="Penalty not found")
    if request.amount != penalty.amount:
        raise HTTPException(status_code=400, detail="Amount does not match penalty")
    return feature_store.save_payment(SandboxPayment(penaltyId=penalty.id, amount=request.amount))
