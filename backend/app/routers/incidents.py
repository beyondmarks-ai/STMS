from fastapi import APIRouter, HTTPException, status

from ..models import Incident, ReviewRequest
from ..store import store

router = APIRouter(prefix="/incidents", tags=["incidents"])


@router.get("", response_model=list[Incident], response_model_by_alias=True)
def list_incidents() -> list[Incident]:
    return store.list_incidents()


@router.patch("/{incident_id}/review", response_model=Incident, response_model_by_alias=True)
def review_incident(incident_id: str, review: ReviewRequest) -> Incident:
    incident = store.review_incident(incident_id, review)
    if incident is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Incident not found")
    return incident
