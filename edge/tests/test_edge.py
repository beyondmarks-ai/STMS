import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from edge.app import CameraRequest, redact_rtsp_url, require_token, settings


def test_rtsp_credentials_are_redacted() -> None:
    assert (
        redact_rtsp_url('rtsp://operator:secret@192.168.1.50:554/live/main?token=x')
        == 'rtsp://192.168.1.50:554/live/main'
    )


def test_camera_request_rejects_non_rtsp_urls() -> None:
    with pytest.raises(ValidationError):
        CameraRequest(cameraName='College Gate', rtspUrl='https://example.test/video')


def test_pairing_token_is_required(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, 'edge_connector_token', 'private-token')
    with pytest.raises(HTTPException) as rejected:
        require_token('wrong-token')
    assert rejected.value.status_code == 401
    assert require_token('private-token') is None
