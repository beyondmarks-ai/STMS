from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "STMS API"
    environment: str = "development"
    storage_account_url: str | None = None
    raw_video_container: str = "raw-video"
    evidence_container: str = "evidence"
    cosmos_endpoint: str | None = None
    cosmos_database: str = "max-traffic"
    azure_ml_endpoint: str | None = None
    azure_ml_deployment: str | None = None
    vision_endpoint: str | None = None
    azure_openai_endpoint: str | None = None
    azure_openai_api_key: str | None = None
    azure_openai_deployment: str | None = None
    azure_face_endpoint: str | None = None
    azure_face_api_key: str | None = None
    dataflag_api_key: str | None = None
    dataflag_endpoint: str = 'https://api.dataflag.in/api/v3/rc-details'
    dataflag_timeout_seconds: float = 30
    demo_processor: bool = False
    max_upload_mb: int = 500
    model_dir: Path = Path(__file__).resolve().parents[1] / "models"
    evidence_dir: Path = Path(__file__).resolve().parents[1] / "runtime" / "evidence"
    inference_fps: float = 2.0
    detection_confidence: float = 0.30
    max_sampled_frames: int = 1800
    automatic_direction_detection: bool = False

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
