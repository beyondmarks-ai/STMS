from datetime import datetime
from typing import Any
from uuid import uuid4

from pydantic import Field, field_validator, model_validator

from .models import CamelModel, utc_now


class VehicleLookupRequest(CamelModel):
    vehicle_number: str = Field(min_length=4, max_length=24)

    @model_validator(mode='before')
    @classmethod
    def accept_camel_case(cls, value: object) -> object:
        if isinstance(value, dict) and 'vehicleNumber' in value:
            return {**value, 'vehicle_number': value['vehicleNumber']}
        return value

    @field_validator('vehicle_number')
    @classmethod
    def normalize_vehicle_number(cls, value: str) -> str:
        normalized = ''.join(character for character in value.upper() if character.isalnum())
        if not 6 <= len(normalized) <= 14:
            raise ValueError('Enter a valid vehicle registration number')
        return normalized


class CreditLedgerEntry(CamelModel):
    id: str = Field(default_factory=lambda: f'LED-{uuid4().hex[:10].upper()}')
    amount: int
    balance_after: int = Field(alias='balanceAfter', ge=0)
    reason: str
    vehicle_number: str | None = Field(default=None, alias='vehicleNumber')
    provider: str | None = None
    created_at: datetime = Field(default_factory=utc_now, alias='createdAt')


class CreditWallet(CamelModel):
    balance: int = Field(ge=0)
    initial_credits: int = Field(default=100, alias='initialCredits')
    lookup_cost: int = Field(default=1, alias='lookupCost')
    provider: str = 'DataFlag'
    configured: bool = False


class VehicleLookupResponse(CamelModel):
    lookup_id: str = Field(default_factory=lambda: f'LOOK-{uuid4().hex[:10].upper()}', alias='lookupId')
    vehicle_number: str = Field(alias='vehicleNumber')
    provider: str = 'DataFlag'
    credits_remaining: int = Field(alias='creditsRemaining', ge=0)
    details: dict[str, Any]
    checked_at: datetime = Field(default_factory=utc_now, alias='checkedAt')
