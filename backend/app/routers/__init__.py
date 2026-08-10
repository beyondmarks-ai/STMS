from .evidence import router as evidence_router
from .incidents import router as incidents_router
from .jobs import router as jobs_router
from .vehicle_lookups import router as vehicle_lookups_router

__all__ = [
    'evidence_router',
    'incidents_router',
    'jobs_router',
    'vehicle_lookups_router',
]
