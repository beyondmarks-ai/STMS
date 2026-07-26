"""Download safe ONNX artifacts used by the local video analyzer."""

from pathlib import Path
from shutil import copy2

from huggingface_hub import hf_hub_download


ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "models"

MODELS = {
    "traffic.onnx": ("webnn/yolo11n", "onnx/yolo11n.onnx"),
    "helmet_plate.onnx": ("2vhoc/helmet-detection-traffic", "stage2/mu_bien_so_stage2.onnx"),
    "plate.onnx": ("ml-debi/yolov8-license-plate-detection", "best.onnx"),
}


def main() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    for target_name, (repo_id, filename) in MODELS.items():
        target = MODEL_DIR / target_name
        if target.exists() and target.stat().st_size > 1024:
            print(f"ready: {target.name}")
            continue
        cached = hf_hub_download(repo_id=repo_id, filename=filename)
        copy2(cached, target)
        print(f"downloaded: {target.name} ({target.stat().st_size / 1_000_000:.1f} MB)")


if __name__ == "__main__":
    main()
