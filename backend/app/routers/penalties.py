from fastapi import APIRouter

from ..models import Penalty, PenaltyTariff, VehiclePenaltySummary
from ..services.penalties import tariffs
from ..store import store

router = APIRouter(prefix="/penalties", tags=["penalties"])


@router.get("", response_model=list[Penalty], response_model_by_alias=True)
def list_penalties() -> list[Penalty]:
    return store.list_penalties()


@router.get(
    "/vehicles",
    response_model=list[VehiclePenaltySummary],
    response_model_by_alias=True,
)
def list_vehicle_penalties() -> list[VehiclePenaltySummary]:
    return store.list_vehicle_penalty_summaries()


@router.get("/tariffs", response_model=list[PenaltyTariff], response_model_by_alias=True)
def list_tariffs() -> list[PenaltyTariff]:
    return tariffs()
