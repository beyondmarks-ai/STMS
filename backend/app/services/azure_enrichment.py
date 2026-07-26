from __future__ import annotations

import base64
import json
from dataclasses import dataclass

import cv2
import httpx
import numpy as np
from azure.identity import DefaultAzureCredential
from azure.core.exceptions import AzureError


@dataclass(frozen=True)
class VehicleEnrichment:
    rider_count: int | None = None
    vehicle_type: str | None = None
    body_style: str | None = None
    color: str | None = None
    make: str | None = None
    model: str | None = None
    description: str | None = None
    confidence: float | None = None
    uncertainties: tuple[str, ...] = ()


class AzureOpenAIVisionEnricher:
    """Enrich one evidence crop without making the primary violation decision."""

    def __init__(
        self,
        endpoint: str | None,
        api_key: str | None,
        deployment: str | None,
        timeout_seconds: float = 45,
    ) -> None:
        self.endpoint = (endpoint or "").rstrip("/")
        self.api_key = api_key or ""
        self.deployment = deployment or ""
        self.timeout_seconds = timeout_seconds
        self.credential = (
            DefaultAzureCredential() if self.endpoint and not self.api_key else None
        )

    @property
    def enabled(self) -> bool:
        return bool(self.endpoint and self.deployment)

    def _headers(self) -> dict[str, str]:
        if self.api_key:
            return {'api-key': self.api_key, 'Content-Type': 'application/json'}
        if self.credential is None:
            return {'Content-Type': 'application/json'}
        token = self.credential.get_token(
            'https://cognitiveservices.azure.com/.default'
        )
        return {
            'Authorization': f'Bearer {token.token}',
            'Content-Type': 'application/json',
        }

    def enrich(
        self, image: np.ndarray, local_rider_count: int | None = None
    ) -> VehicleEnrichment | None:
        if not self.enabled or image.size == 0:
            return None
        encoded = self._encode_image(image)
        if not encoded:
            return None
        prompt = (
            "Inspect only the motorcycle/scooter and people physically riding it in "
            "this crop. Do not count nearby pedestrians or riders on other vehicles. "
            "Report only directly visible evidence. Use null when make or model is not "
            "reliably visible; never invent an owner or person's identity. "
            f"The tracking pipeline estimated {local_rider_count or 'unknown'} riders. "
            "Return JSON with riderCount, vehicleType, bodyStyle, color, make, model, "
            "description, confidence (0 to 1), and uncertainties (array of strings)."
        )
        payload = {
            "model": self.deployment,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are a cautious traffic-evidence analyst. Output JSON only. "
                        "Prefer unknown/null over speculation."
                    ),
                },
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{encoded}",
                                "detail": "high",
                            },
                        },
                    ],
                },
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0,
            "max_tokens": 500,
        }
        try:
            response = httpx.post(
                f"{self.endpoint}/openai/v1/chat/completions",
                headers=self._headers(),
                json=payload,
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            values = json.loads(content)
            return self._from_json(values)
        except (
            AzureError,
            httpx.HTTPError,
            KeyError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
        ):
            return None

    @staticmethod
    def _encode_image(image: np.ndarray) -> str | None:
        height, width = image.shape[:2]
        scale = min(1.0, 1600 / max(height, width))
        if scale < 1:
            image = cv2.resize(
                image,
                (max(1, round(width * scale)), max(1, round(height * scale))),
                interpolation=cv2.INTER_AREA,
            )
        ok, buffer = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 88])
        return base64.b64encode(buffer).decode("ascii") if ok else None

    @staticmethod
    def _from_json(values: dict[str, object]) -> VehicleEnrichment:
        def text(key: str) -> str | None:
            value = values.get(key)
            if not isinstance(value, str):
                return None
            cleaned = value.strip()
            return (
                cleaned
                if cleaned and cleaned.lower() not in {"unknown", "null", "n/a"}
                else None
            )

        rider_count = values.get("riderCount")
        if not isinstance(rider_count, int) or not 0 <= rider_count <= 6:
            rider_count = None
        confidence = values.get("confidence")
        if not isinstance(confidence, (int, float)):
            confidence = None
        else:
            confidence = min(1.0, max(0.0, float(confidence)))
        uncertainties = values.get("uncertainties")
        return VehicleEnrichment(
            rider_count=rider_count,
            vehicle_type=text("vehicleType"),
            body_style=text("bodyStyle"),
            color=text("color"),
            make=text("make"),
            model=text("model"),
            description=text("description"),
            confidence=confidence,
            uncertainties=tuple(
                str(item).strip() for item in uncertainties if str(item).strip()
            )
            if isinstance(uncertainties, list)
            else (),
        )


class AzureFaceCropper:
    """Use Azure Face only for a rectangle; do not request a face ID."""

    def __init__(
        self,
        endpoint: str | None,
        api_key: str | None,
        timeout_seconds: float = 20,
    ) -> None:
        self.endpoint = (endpoint or "").rstrip("/")
        self.api_key = api_key or ""
        self.timeout_seconds = timeout_seconds
        self.credential = (
            DefaultAzureCredential() if self.endpoint and not self.api_key else None
        )

    @property
    def enabled(self) -> bool:
        return bool(self.endpoint)

    def _headers(self) -> dict[str, str]:
        headers = {'Content-Type': 'application/octet-stream'}
        if self.api_key:
            headers['Ocp-Apim-Subscription-Key'] = self.api_key
        elif self.credential is not None:
            token = self.credential.get_token(
                'https://cognitiveservices.azure.com/.default'
            )
            headers['Authorization'] = f'Bearer {token.token}'
        return headers

    def crop_largest(self, image: np.ndarray) -> np.ndarray | None:
        if not self.enabled or image.size == 0:
            return None
        ok, buffer = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 92])
        if not ok:
            return None
        try:
            response = httpx.post(
                f"{self.endpoint}/face/v1.2/detect",
                params={
                    "_overload": "detect",
                    "detectionModel": "detection_03",
                    "returnFaceId": "false",
                },
                headers=self._headers(),
                content=buffer.tobytes(),
                timeout=self.timeout_seconds,
            )
            response.raise_for_status()
            faces = response.json()
            if not isinstance(faces, list) or not faces:
                return None
            rectangle = max(
                (item.get("faceRectangle", {}) for item in faces),
                key=lambda item: int(item.get("width", 0))
                * int(item.get("height", 0)),
            )
            left, top = int(rectangle["left"]), int(rectangle["top"])
            width, height = int(rectangle["width"]), int(rectangle["height"])
            padding = round(max(width, height) * .18)
            x1, y1 = max(0, left - padding), max(0, top - padding)
            x2 = min(image.shape[1], left + width + padding)
            y2 = min(image.shape[0], top + height + padding)
            crop = image[y1:y2, x1:x2]
            return crop.copy() if crop.size else None
        except (AzureError, httpx.HTTPError, KeyError, TypeError, ValueError):
            return None
