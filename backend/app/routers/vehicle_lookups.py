from fastapi import APIRouter, HTTPException, status

from ..config import get_settings
from ..credit_store import credit_store
from ..services.dataflag import DataFlagClient, DataFlagError, DataFlagNoDetailsError
from ..vehicle_models import (
    CreditLedgerEntry,
    CreditWallet,
    VehicleLookupRequest,
    VehicleLookupResponse,
)

router = APIRouter(prefix='/vehicle-lookups', tags=['vehicle-lookups'])
settings = get_settings()
client = DataFlagClient(
    settings.dataflag_api_key,
    settings.dataflag_endpoint,
    settings.dataflag_timeout_seconds,
)


@router.get('/wallet', response_model=CreditWallet, response_model_by_alias=True)
def get_wallet() -> CreditWallet:
    return credit_store.get_wallet(client.configured)


@router.get(
    '/ledger',
    response_model=list[CreditLedgerEntry],
    response_model_by_alias=True,
)
def get_ledger() -> list[CreditLedgerEntry]:
    return credit_store.list_ledger()


@router.post(
    '',
    response_model=VehicleLookupResponse,
    response_model_by_alias=True,
)
def lookup_vehicle(request: VehicleLookupRequest) -> VehicleLookupResponse:
    wallet = credit_store.get_wallet(client.configured)
    if not client.configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='DataFlag lookup is not configured',
        )
    if wallet.balance < wallet.lookup_cost:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail='No vehicle lookup credits remaining',
        )
    try:
        details = client.lookup(request.vehicle_number)
    except DataFlagNoDetailsError as exception:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exception),
        ) from exception
    except DataFlagError as exception:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exception),
        ) from exception
    ledger = credit_store.charge_lookup(request.vehicle_number)
    if ledger is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Credit balance changed; retry the lookup',
        )
    return VehicleLookupResponse(
        vehicleNumber=request.vehicle_number,
        creditsRemaining=ledger.balance_after,
        details=details,
    )
