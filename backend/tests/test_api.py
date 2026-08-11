import os

os.environ["DEMO_PROCESSOR"] = "true"

from fastapi.testclient import TestClient

from app.main import app


client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_root_describes_service() -> None:
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["docs"] == "/docs"


def test_upload_process_and_review() -> None:
    response = client.post(
        "/api/v1/jobs",
        data={"camera": "Test Junction"},
        files={"video": ("traffic.mp4", b"representative demo bytes", "video/mp4")},
    )
    assert response.status_code == 202
    job_id = response.json()["id"]
    job = client.get(f"/api/v1/jobs/{job_id}").json()
    assert job["status"] == "completed"
    incidents = client.get("/api/v1/incidents").json()
    incident = next(item for item in incidents if item["jobId"] == job_id)
    reviewed = client.patch(
        f"/api/v1/incidents/{incident['id']}/review",
        json={"status": "approved", "note": "Evidence checked"},
    )
    assert reviewed.status_code == 200
    assert reviewed.json()["status"] == "approved"
    assert reviewed.json()["note"] == "Evidence checked"
    penalties = client.get("/api/v1/penalties").json()
    penalty = next(item for item in penalties if item["incidentId"] == incident["id"])
    assert penalty["status"] == "confirmed"
    assert penalty["plate"] != "Unreadable"
