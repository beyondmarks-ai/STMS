from app.models import Incident, ReviewRequest, ReviewStatus, ViolationType
from app.store import MemoryStore


def incident(identifier: str, plate: str, kind: ViolationType) -> Incident:
    return Incident(
        id=identifier,
        type=kind,
        plate=plate,
        camera="College Gate",
        confidence=.91,
        explanation="Verified temporal detection.",
        jobId="JOB-TEST",
    )


def test_skips_unreadable_ocr_and_prevents_duplicate_penalty() -> None:
    store = MemoryStore()
    readable = incident("INC-READABLE", "KA38EB9843", ViolationType.no_helmet)
    store.save_incident(readable)
    store.save_incident(readable)
    store.save_incident(
        incident("INC-UNREADABLE", "Unreadable", ViolationType.wrong_side)
    )

    penalties = store.list_penalties()
    assert len(penalties) == 1
    assert penalties[0].plate == "KA 38 EB 9843"
    assert penalties[0].amount == 1000


def test_accumulates_same_vehicle_and_tracks_review_status() -> None:
    store = MemoryStore()
    store.save_incident(
        incident("INC-ONE", "KA 38 EB 9843", ViolationType.no_helmet)
    )
    store.save_incident(
        incident("INC-TWO", "KA38EB9843", ViolationType.ambulance_obstruction)
    )

    summary = store.list_vehicle_penalty_summaries()[0]
    assert summary.plate == "KA 38 EB 9843"
    assert summary.penalty_count == 2
    assert summary.total_amount == 11000
    assert summary.pending_count == 2

    store.review_incident(
        "INC-ONE",
        ReviewRequest(status=ReviewStatus.approved, note="Evidence checked"),
    )
    store.review_incident(
        "INC-TWO",
        ReviewRequest(status=ReviewStatus.rejected, note="False detection"),
    )

    penalties = {item.incident_id: item for item in store.list_penalties()}
    assert penalties["INC-ONE"].status.value == "confirmed"
    assert penalties["INC-TWO"].status.value == "void"
    summary = store.list_vehicle_penalty_summaries()[0]
    assert summary.penalty_count == 1
    assert summary.confirmed_amount == 1000


def test_fixed_tariff_api() -> None:
    from app.main import app
    from fastapi.testclient import TestClient

    response = TestClient(app).get("/api/v1/penalties/tariffs")
    assert response.status_code == 200
    tariffs = {item["violationType"]: item["amount"] for item in response.json()}
    assert tariffs == {
        "noHelmet": 1000,
        "tripleRiding": 1000,
        "wrongSide": 500,
        "ambulanceObstruction": 10000,
    }
