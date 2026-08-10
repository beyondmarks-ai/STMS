from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from tempfile import TemporaryDirectory
from threading import Event, RLock, Thread
from time import monotonic
from urllib.parse import urlsplit, urlunsplit
from uuid import uuid4

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


class Settings(BaseSettings):
    connector_name: str = 'STMS College Edge Connector'
    edge_connector_token: str = ''
    stms_api_base_url: str = (
        'https://stmsprod-api.wonderfulgrass-31348be0.centralindia.azurecontainerapps.io'
    )
    max_cameras: int = 2
    ffmpeg_path: str = 'ffmpeg'
    ffprobe_path: str = 'ffprobe'

    model_config = SettingsConfigDict(env_file='edge/.env', extra='ignore')


settings = Settings()


class CamelModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True)


class CameraRequest(CamelModel):
    camera_name: str = Field(alias='cameraName', min_length=2, max_length=120)
    rtsp_url: str = Field(alias='rtspUrl', min_length=8, max_length=2048)
    segment_seconds: int = Field(default=8, alias='segmentSeconds', ge=5, le=20)
    interval_seconds: int = Field(
        default=60,
        alias='intervalSeconds',
        ge=20,
        le=600,
    )
    capture_fps: int = Field(default=8, alias='captureFps', ge=2, le=15)

    @field_validator('rtsp_url')
    @classmethod
    def validate_rtsp_url(cls, value: str) -> str:
        parsed = urlsplit(value.strip())
        if parsed.scheme.lower() not in {'rtsp', 'rtsps'} or not parsed.hostname:
            raise ValueError('A valid rtsp:// or rtsps:// camera URL is required')
        return value.strip()

    @field_validator('interval_seconds')
    @classmethod
    def validate_interval(cls, value: int, info) -> int:
        segment = info.data.get('segment_seconds', 8)
        if value < segment:
            raise ValueError('Interval must not be shorter than the segment')
        return value


class ProbeResponse(CamelModel):
    reachable: bool
    endpoint: str
    codec: str | None = None
    width: int | None = None
    height: int | None = None
    message: str


class CameraStatus(CamelModel):
    id: str
    camera_name: str = Field(alias='cameraName')
    endpoint: str
    state: str
    segment_seconds: int = Field(alias='segmentSeconds')
    interval_seconds: int = Field(alias='intervalSeconds')
    last_job_id: str | None = Field(default=None, alias='lastJobId')
    last_upload_at: datetime | None = Field(default=None, alias='lastUploadAt')
    last_error: str | None = Field(default=None, alias='lastError')
    consecutive_failures: int = Field(default=0, alias='consecutiveFailures')
    started_at: datetime = Field(default_factory=utc_now, alias='startedAt')


@dataclass
class CameraSession:
    id: str
    request: CameraRequest
    endpoint: str
    stop_event: Event = field(default_factory=Event)
    state: str = 'starting'
    last_job_id: str | None = None
    last_upload_at: datetime | None = None
    last_error: str | None = None
    consecutive_failures: int = 0
    started_at: datetime = field(default_factory=utc_now)

    def response(self) -> CameraStatus:
        return CameraStatus(
            id=self.id,
            cameraName=self.request.camera_name,
            endpoint=self.endpoint,
            state=self.state,
            segmentSeconds=self.request.segment_seconds,
            intervalSeconds=self.request.interval_seconds,
            lastJobId=self.last_job_id,
            lastUploadAt=self.last_upload_at,
            lastError=self.last_error,
            consecutiveFailures=self.consecutive_failures,
            startedAt=self.started_at,
        )


class CameraManager:
    def __init__(self) -> None:
        self._sessions: dict[str, CameraSession] = {}
        self._lock = RLock()

    def probe(self, request: CameraRequest) -> ProbeResponse:
        executable = shutil.which(settings.ffprobe_path)
        if executable is None:
            raise RuntimeError('FFprobe is not installed or not available on PATH')
        command = [
            executable,
            '-v',
            'error',
            '-rtsp_transport',
            'tcp',
            '-timeout',
            '7000000',
            '-select_streams',
            'v:0',
            '-show_entries',
            'stream=codec_name,width,height',
            '-of',
            'json',
            request.rtsp_url,
        ]
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=12,
                check=False,
                creationflags=_hidden_process_flags(),
            )
        except subprocess.TimeoutExpired as exception:
            raise RuntimeError('RTSP connection timed out after 12 seconds') from exception
        if completed.returncode != 0:
            raise RuntimeError(
                'Camera rejected the connection or the RTSP path is unavailable'
            )
        try:
            streams = json.loads(completed.stdout).get('streams', [])
            stream = streams[0]
        except (json.JSONDecodeError, IndexError, KeyError, TypeError) as exception:
            raise RuntimeError('RTSP endpoint returned no readable video stream') from exception
        return ProbeResponse(
            reachable=True,
            endpoint=redact_rtsp_url(request.rtsp_url),
            codec=stream.get('codec_name'),
            width=stream.get('width'),
            height=stream.get('height'),
            message='Camera stream is reachable over RTSP/TCP',
        )

    def start(self, request: CameraRequest) -> CameraStatus:
        self.probe(request)
        with self._lock:
            running = [
                session
                for session in self._sessions.values()
                if session.state not in {'stopped'}
            ]
            if len(running) >= settings.max_cameras:
                raise RuntimeError(
                    f'Connector camera limit reached ({settings.max_cameras})'
                )
            camera_id = f'CAM-{uuid4().hex[:8].upper()}'
            session = CameraSession(
                id=camera_id,
                request=request,
                endpoint=redact_rtsp_url(request.rtsp_url),
            )
            self._sessions[camera_id] = session
            Thread(
                target=self._run,
                args=(session,),
                name=f'stms-{camera_id.lower()}',
                daemon=True,
            ).start()
            return session.response()

    def stop(self, camera_id: str) -> CameraStatus | None:
        with self._lock:
            session = self._sessions.get(camera_id)
            if session is None:
                return None
            session.stop_event.set()
            session.state = 'stopping'
            return session.response()

    def get(self, camera_id: str) -> CameraStatus | None:
        with self._lock:
            session = self._sessions.get(camera_id)
            return session.response() if session else None

    def list(self) -> list[CameraStatus]:
        with self._lock:
            return [session.response() for session in self._sessions.values()]

    def _run(self, session: CameraSession) -> None:
        with TemporaryDirectory(prefix=f'stms-{session.id.lower()}-') as directory:
            output = Path(directory) / 'segment.mp4'
            while not session.stop_event.is_set():
                started = monotonic()
                try:
                    session.state = 'capturing'
                    self._capture(session, output)
                    if session.stop_event.is_set():
                        break
                    session.state = 'uploading'
                    job_id = self._upload(session, output)
                    session.last_job_id = job_id
                    session.last_upload_at = utc_now()
                    session.last_error = None
                    session.consecutive_failures = 0
                    session.state = 'monitoring'
                except Exception:
                    session.consecutive_failures += 1
                    session.last_error = (
                        'Camera capture or Azure upload failed; reconnecting automatically'
                    )
                    session.state = 'reconnecting'
                finally:
                    output.unlink(missing_ok=True)

                elapsed = monotonic() - started
                normal_wait = max(1, session.request.interval_seconds - elapsed)
                retry_wait = min(30, 3 * max(1, session.consecutive_failures))
                session.stop_event.wait(
                    retry_wait if session.consecutive_failures else normal_wait
                )
        session.state = 'stopped'

    def _capture(self, session: CameraSession, output: Path) -> None:
        executable = shutil.which(settings.ffmpeg_path)
        if executable is None:
            raise RuntimeError('FFmpeg is not installed or not available on PATH')
        command = [
            executable,
            '-hide_banner',
            '-loglevel',
            'error',
            '-rtsp_transport',
            'tcp',
            '-i',
            session.request.rtsp_url,
            '-t',
            str(session.request.segment_seconds),
            '-vf',
            f'fps={session.request.capture_fps},scale=1280:-2:force_original_aspect_ratio=decrease',
            '-an',
            '-c:v',
            'libx264',
            '-preset',
            'veryfast',
            '-pix_fmt',
            'yuv420p',
            '-movflags',
            '+faststart',
            '-y',
            str(output),
        ]
        completed = subprocess.run(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=session.request.segment_seconds + 25,
            check=False,
            creationflags=_hidden_process_flags(),
        )
        if completed.returncode != 0 or not output.exists() or output.stat().st_size < 1024:
            raise RuntimeError('RTSP segment capture failed')

    def _upload(self, session: CameraSession, output: Path) -> str:
        url = f"{settings.stms_api_base_url.rstrip('/')}/api/v1/jobs"
        with output.open('rb') as stream:
            response = httpx.post(
                url,
                data={'camera': session.request.camera_name},
                files={'video': (f'{session.id}.mp4', stream, 'video/mp4')},
                timeout=120,
            )
        response.raise_for_status()
        payload = response.json()
        job_id = payload.get('id')
        if not isinstance(job_id, str):
            raise RuntimeError('STMS API returned no job identifier')
        return job_id


def redact_rtsp_url(value: str) -> str:
    parsed = urlsplit(value)
    host = parsed.hostname or ''
    if ':' in host and not host.startswith('['):
        host = f'[{host}]'
    if parsed.port:
        host = f'{host}:{parsed.port}'
    return urlunsplit((parsed.scheme, host, parsed.path, '', ''))


def _hidden_process_flags() -> int:
    return subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0


def require_token(x_edge_token: str | None = Header(default=None)) -> None:
    if not settings.edge_connector_token:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='EDGE_CONNECTOR_TOKEN is not configured',
        )
    if x_edge_token != settings.edge_connector_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid edge connector token',
        )


manager = CameraManager()
app = FastAPI(title=settings.connector_name, version='1.0.0')


@app.get('/health')
def health() -> dict[str, object]:
    return {
        'status': 'healthy',
        'configured': bool(settings.edge_connector_token),
        'ffmpeg': shutil.which(settings.ffmpeg_path) is not None,
        'activeCameras': len(
            [camera for camera in manager.list() if camera.state != 'stopped']
        ),
    }


@app.post('/api/v1/cameras/test', response_model=ProbeResponse, response_model_by_alias=True)
def test_camera(
    request: CameraRequest,
    _: None = Depends(require_token),
) -> ProbeResponse:
    try:
        return manager.probe(request)
    except RuntimeError as exception:
        raise HTTPException(status_code=422, detail=str(exception)) from exception


@app.post('/api/v1/cameras', response_model=CameraStatus, response_model_by_alias=True)
def start_camera(
    request: CameraRequest,
    _: None = Depends(require_token),
) -> CameraStatus:
    try:
        return manager.start(request)
    except RuntimeError as exception:
        raise HTTPException(status_code=422, detail=str(exception)) from exception


@app.get('/api/v1/cameras', response_model=list[CameraStatus], response_model_by_alias=True)
def list_cameras(_: None = Depends(require_token)) -> list[CameraStatus]:
    return manager.list()


@app.get('/api/v1/cameras/{camera_id}', response_model=CameraStatus, response_model_by_alias=True)
def get_camera(
    camera_id: str,
    _: None = Depends(require_token),
) -> CameraStatus:
    camera = manager.get(camera_id)
    if camera is None:
        raise HTTPException(status_code=404, detail='Camera session not found')
    return camera


@app.delete('/api/v1/cameras/{camera_id}', response_model=CameraStatus, response_model_by_alias=True)
def stop_camera(
    camera_id: str,
    _: None = Depends(require_token),
) -> CameraStatus:
    camera = manager.stop(camera_id)
    if camera is None:
        raise HTTPException(status_code=404, detail='Camera session not found')
    return camera
