from __future__ import annotations

import mimetypes
from pathlib import Path
from typing import Protocol

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings

from .config import Settings


class ObjectStorage(Protocol):
    is_cloud: bool

    def upload_source(self, blob_name: str, path: Path) -> None: ...

    def download_source(self, blob_name: str, path: Path) -> None: ...

    def upload_evidence_tree(self, job_id: str, directory: Path) -> None: ...

    def read_evidence(self, blob_name: str) -> tuple[bytes, str]: ...


class LocalObjectStorage:
    is_cloud = False

    def upload_source(self, blob_name: str, path: Path) -> None:
        return None

    def download_source(self, blob_name: str, path: Path) -> None:
        raise FileNotFoundError(blob_name)

    def upload_evidence_tree(self, job_id: str, directory: Path) -> None:
        return None

    def read_evidence(self, blob_name: str) -> tuple[bytes, str]:
        raise FileNotFoundError(blob_name)


class AzureBlobStorage:
    is_cloud = True

    def __init__(self, settings: Settings) -> None:
        if not settings.storage_account_url:
            raise ValueError('STORAGE_ACCOUNT_URL is required')
        service = BlobServiceClient(
            settings.storage_account_url,
            credential=DefaultAzureCredential(),
        )
        self._raw = service.get_container_client(settings.raw_video_container)
        self._evidence = service.get_container_client(settings.evidence_container)

    def upload_source(self, blob_name: str, path: Path) -> None:
        content_type = mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
        with path.open('rb') as stream:
            self._raw.upload_blob(
                blob_name,
                stream,
                overwrite=True,
                content_settings=ContentSettings(content_type=content_type),
            )

    def download_source(self, blob_name: str, path: Path) -> None:
        with path.open('wb') as stream:
            self._raw.download_blob(blob_name).readinto(stream)

    def upload_evidence_tree(self, job_id: str, directory: Path) -> None:
        if not directory.exists():
            return
        for path in directory.rglob('*'):
            if not path.is_file():
                continue
            relative = path.relative_to(directory).as_posix()
            blob_name = f'{job_id}/{relative}'
            content_type = mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
            with path.open('rb') as stream:
                self._evidence.upload_blob(
                    blob_name,
                    stream,
                    overwrite=True,
                    content_settings=ContentSettings(content_type=content_type),
                )

    def read_evidence(self, blob_name: str) -> tuple[bytes, str]:
        downloader = self._evidence.download_blob(blob_name)
        content_type = (
            downloader.properties.content_settings.content_type
            or 'application/octet-stream'
        )
        return downloader.readall(), content_type


def create_object_storage(settings: Settings) -> ObjectStorage:
    if settings.storage_account_url:
        return AzureBlobStorage(settings)
    return LocalObjectStorage()
