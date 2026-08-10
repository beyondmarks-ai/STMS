from typing import Any

import httpx


class DataFlagError(RuntimeError):
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
        if isinstance(payload, dict):
            return payload
        return {'result': payload}
