from typing import Any

import httpx


class DataFlagError(RuntimeError):
    pass


class DataFlagNoDetailsError(DataFlagError):
    pass


class DataFlagClient:
    def __init__(
        self,
        api_key: str | None,
        endpoint: str,
        timeout_seconds: float = 30,
    ) -> None:
        self.api_key = (api_key or '').strip()
        self.endpoint = endpoint
        self.timeout_seconds = timeout_seconds

    @property
    def configured(self) -> bool:
        return bool(self.api_key)

    def lookup(self, vehicle_number: str) -> dict[str, Any]:
        if not self.configured:
            raise DataFlagError('DataFlag API key is not configured')
        try:
            response = httpx.post(
                self.endpoint,
                headers={
                    'X-API-KEY': self.api_key,
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                },
                json={'vehiclenumber': vehicle_number},
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exception:
            raise DataFlagError('DataFlag lookup failed') from exception
        if not isinstance(payload, dict):
            raise DataFlagError('DataFlag returned an invalid response')
        return self._extract_vehicle_details(payload)

    @staticmethod
    def _extract_vehicle_details(payload: dict[str, Any]) -> dict[str, Any]:
        candidate = payload
        for _ in range(3):
            nested = next(
                (candidate.get(key) for key in ('data', 'result', 'response', 'rc_details', 'rcDetails') if isinstance(candidate.get(key), dict)),
                None,
            )
            if not isinstance(nested, dict):
                break
            candidate = nested

        details = {
            key: value
            for key, value in candidate.items()
            if key.lower() not in {'credits_balance', 'credits_charged'}
        }
        normalized_keys = {
            ''.join(character for character in key.lower() if character.isalnum())
            for key in details
        }
        identifying_fields = {
            'registrationnumber',
            'registrationno',
            'regnno',
            'regnnumber',
            'vehiclemodel',
            'makermodel',
            'maker',
            'vehiclemanufacturer',
            'ownername',
        }
        if not normalized_keys.intersection(identifying_fields):
            raise DataFlagNoDetailsError('DataFlag returned no vehicle details for this registration')
        return details
