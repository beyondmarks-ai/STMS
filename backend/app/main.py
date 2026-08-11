from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .config import get_settings
from .models import HealthResponse
from .routers import (
    evidence_router,
    incidents_router,
    jobs_router,
    penalties_router,
    vehicle_lookups_router,
)

settings = get_settings()
settings.evidence_dir.mkdir(parents=True, exist_ok=True)
app = FastAPI(title=settings.app_name, version='1.0.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=['http://localhost', 'http://127.0.0.1'],
    allow_methods=['GET', 'POST', 'PATCH', 'OPTIONS'],
    allow_headers=['Authorization', 'Content-Type'],
)
app.include_router(jobs_router, prefix='/api/v1')
app.include_router(incidents_router, prefix='/api/v1')
app.include_router(penalties_router, prefix='/api/v1')
app.include_router(vehicle_lookups_router, prefix='/api/v1')
if settings.storage_account_url:
    app.include_router(evidence_router, prefix='/api/v1')
else:
    app.mount(
        '/api/v1/evidence',
        StaticFiles(directory=settings.evidence_dir),
        name='evidence',
    )


@app.get('/', include_in_schema=False)
def root() -> dict[str, str]:
    return {
        'name': settings.app_name,
        'status': 'healthy',
        'processor': 'demo' if settings.demo_processor else 'local-onnx',
        'health': '/health',
        'docs': '/docs',
    }


@app.get('/health', response_model=HealthResponse, response_model_by_alias=True)
def health() -> HealthResponse:
    return HealthResponse(
        status='healthy',
        environment=settings.environment,
        processor='demo' if settings.demo_processor else 'local-onnx',
    )
