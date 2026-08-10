from pathlib import Path
from tempfile import NamedTemporaryFile

from fastapi import (
    APIRouter,
    BackgroundTasks,
    File,
    Form,
    HTTPException,
    UploadFile,
    status,
)

from ..config import get_settings
from ..models import JobStatus, ProcessingJob
from ..services.processor import DemoVideoProcessor, RealVideoProcessor
from ..storage import create_object_storage
from ..store import store

router = APIRouter(prefix='/jobs', tags=['jobs'])
settings = get_settings()
object_storage = create_object_storage(settings)


@router.get('', response_model=list[ProcessingJob], response_model_by_alias=True)
def list_jobs() -> list[ProcessingJob]:
    return store.list_jobs()


@router.get('/{job_id}', response_model=ProcessingJob, response_model_by_alias=True)
def get_job(job_id: str) -> ProcessingJob:
    job = store.get_job(job_id)
    if job is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Job not found',
        )
    return job


@router.post(
    '',
    response_model=ProcessingJob,
    response_model_by_alias=True,
    status_code=status.HTTP_202_ACCEPTED,
)
async def create_job(
    background_tasks: BackgroundTasks,
    video: UploadFile = File(...),
    camera: str = Form(..., min_length=2, max_length=120),
) -> ProcessingJob:
    original_name = Path(video.filename or 'traffic.mp4').name
    suffix = Path(original_name).suffix.lower()
    if suffix not in {'.mp4', '.mov', '.avi', '.mkv'}:
        raise HTTPException(status_code=415, detail='Unsupported video format')

    temporary = NamedTemporaryFile(prefix='stms-', suffix=suffix, delete=False)
    received = 0
    limit = settings.max_upload_mb * 1024 * 1024
    try:
        while chunk := await video.read(1024 * 1024):
            received += len(chunk)
            if received > limit:
                raise HTTPException(
                    status_code=413,
                    detail='Video exceeds configured upload limit',
                )
            temporary.write(chunk)
    except Exception:
        temporary.close()
        Path(temporary.name).unlink(missing_ok=True)
        raise
    finally:
        if not temporary.closed:
            temporary.close()

    video_path = Path(temporary.name)
    job = ProcessingJob(file_name=original_name, camera=camera)
    source_blob = f'{job.id}/{original_name}' if object_storage.is_cloud else None
    job = store.save_job(job.model_copy(update={'source_blob': source_blob}))
    try:
        if source_blob:
            object_storage.upload_source(source_blob, video_path)
    except Exception as exception:
        video_path.unlink(missing_ok=True)
        store.save_job(
            job.model_copy(
                update={'status': JobStatus.failed, 'error': f'Upload failed: {exception}'}
            )
        )
        raise HTTPException(status_code=502, detail='Azure video upload failed') from exception

    job = store.save_job(
        job.model_copy(update={'status': JobStatus.processing, 'progress': 0.05})
    )
    background_tasks.add_task(process_job, job, video_path)
    return job


def process_job(job: ProcessingJob, video_path: Path) -> None:
    processor = DemoVideoProcessor() if settings.demo_processor else RealVideoProcessor()
    try:
        processor.process(job, video_path, store)
        object_storage.upload_evidence_tree(
            job.id,
            settings.evidence_dir / job.id,
        )
    except Exception as exception:
        store.save_job(
            job.model_copy(update={'status': JobStatus.failed, 'error': str(exception)})
        )
    finally:
        video_path.unlink(missing_ok=True)
