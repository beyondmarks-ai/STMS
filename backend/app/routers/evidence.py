from pathlib import PurePosixPath

from azure.core.exceptions import ResourceNotFoundError
from fastapi import APIRouter, HTTPException, Response, status

from ..config import get_settings
from ..storage import create_object_storage

router = APIRouter(prefix='/evidence', tags=['evidence'])
object_storage = create_object_storage(get_settings())


@router.get('/{blob_path:path}', response_class=Response)
def get_evidence(blob_path: str) -> Response:
    path = PurePosixPath(blob_path)
    if path.is_absolute() or '..' in path.parts or len(path.parts) < 3:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND)
    try:
        content, content_type = object_storage.read_evidence(path.as_posix())
    except (ResourceNotFoundError, FileNotFoundError) as exception:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Evidence not found',
        ) from exception
    return Response(
        content=content,
        media_type=content_type,
        headers={'Cache-Control': 'private, max-age=300'},
    )
