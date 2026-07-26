from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import APIRouter, BackgroundTasks, File, Form, HTTPException, UploadFile, status

from ..config import get_settings
from ..models import JobStatus, ProcessingJob
from ..services.processor import DemoVideoProcessor, RealVideoProcessor
from ..store import store

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("", response_model=list[ProcessingJob], response_model_by_alias=True)
def list_jobs() -> list[ProcessingJob]:
    return store.list_jobs()


@router.get("/{job_id}", response_model=ProcessingJob, response_model_by_alias=True)
def get_job(job_id: str) -> ProcessingJob:
    job = store.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    return job


@router.post("", response_model=ProcessingJob, response_model_by_alias=True, status_code=status.HTTP_202_ACCEPTED)
async def create_job(
    background_tasks: BackgroundTasks,
    video: UploadFile = File(...),
    camera: str = Form(..., min_length=2, max_length=120),
) -> ProcessingJob:
    settings = get_settings()
    suffix = Path(video.filename or "traffic.mp4").suffix.lower()
    if suffix not in {".mp4", ".mov", ".avi", ".mkv"}:
        raise HTTPException(status_code=415, detail="Unsupported video format")
    temporary = NamedTemporaryFile(prefix="max-traffic-", suffix=suffix, delete=False)
    received = 0
    limit = settings.max_upload_mb * 1024 * 1024
    try:
        while chunk := await video.read(1024 * 1024):
            received += len(chunk)
            if received > limit:
                raise HTTPException(status_code=413, detail="Video exceeds configured upload limit")
            temporary.write(chunk)
    except Exception:
        temporary.close()
        Path(temporary.name).unlink(missing_ok=True)
        raise
    finally:
        if not temporary.closed:
            temporary.close()
    job = store.save_job(ProcessingJob(file_name=video.filename or "traffic.mp4", camera=camera, status=JobStatus.processing, progress=.05))
    background_tasks.add_task(_process_job, job, Path(temporary.name))
    return job


def _process_job(job: ProcessingJob, video_path: Path) -> None:
    settings = get_settings()
    processor = DemoVideoProcessor() if settings.demo_processor else RealVideoProcessor()
    try:
        processor.process(job, video_path, store)
    except Exception as exception:
        store.save_job(job.model_copy(update={"status": JobStatus.failed, "error": str(exception)}))
    finally:
        video_path.unlink(missing_ok=True)
