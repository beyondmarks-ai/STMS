"""Run the real local analyzer against a video and print incident evidence."""

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.models import ProcessingJob
from app.services.video_analyzer import VideoAnalyzer


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("video", type=Path)
    parser.add_argument("--camera", default="Validation camera")
    parser.add_argument("--fps", type=float, default=None)
    parser.add_argument("--automatic-direction", action="store_true")
    args = parser.parse_args()
    settings = get_settings()
    analyzer = VideoAnalyzer(
        settings.model_dir,
        settings.evidence_dir,
        settings.detection_confidence,
        args.fps or settings.inference_fps,
        settings.max_sampled_frames,
        args.automatic_direction,
    )
    job = ProcessingJob(fileName=args.video.name, camera=args.camera)

    def progress(value: float) -> None:
        print(f"progress {value * 100:.0f}%", flush=True)

    incidents = analyzer.analyze(job, args.video, progress)
    print(json.dumps(
        [item.model_dump(by_alias=True, mode="json") for item in incidents],
        indent=2,
    ))
    print(f"completed: {len(incidents)} incident(s)")


if __name__ == "__main__":
    main()
