# Runtime models

Run `python tools/download_models.py` from `backend/` to download the safe ONNX artifacts. Binary model files are intentionally excluded from source control.

- `traffic.onnx`: YOLO11n COCO detector (`webnn/yolo11n`, AGPL-3.0)
- `helmet_plate.onnx`: traffic helmet/plate detector (`2vhoc/helmet-detection-traffic`)
- `plate.onnx`: plate localizer (`ml-debi/yolov8-license-plate-detection`, MIT)

Model output is advisory and requires human review. Replace these bootstrap models with an Azure ML model trained and validated on representative Indian traffic footage before a field pilot.
