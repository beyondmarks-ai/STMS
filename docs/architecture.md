# Architecture

```text
Flutter operator app
        |
        | HTTPS
        v
Azure Container Apps / FastAPI
        |                    |
        |                    +-> Cosmos DB (jobs, incidents, reviews)
        |                    +-> Private Blob Storage (source and evidence)
        v
ONNX detector + tracker + temporal rules
        |
        +-> local plate OCR
        +-> Azure OpenAI evidence verification
        +-> Azure Face detection on keyframes only
```

For a college IP camera, a local edge connector runs inside the camera LAN. The phone sends the RTSP URL and pairing token only to that connector. It captures bounded H.264 segments and uploads them to the existing Azure job API over HTTPS; the private RTSP address and credentials never enter Blob Storage or Cosmos DB.

The deployed API accepts an upload, persists the source in Blob Storage and immediately returns a Cosmos-backed job. One always-on Container App currently performs background ONNX inference and writes private evidence to Blob Storage. Before scaling beyond one API replica, processing should move to a queue-triggered Container Apps Job with leases, retries and dead-letter handling.

## Model contract

The inference endpoint must return incident candidates rather than raw boxes alone. Every candidate must contain:

- job, camera, model, and calibration versions;
- violation type and confidence;
- first/last timestamps and associated track IDs;
- raw and normalized OCR candidates;
- rule explanation;
- full-frame, vehicle, plate, face/head, and context-clip blob paths.

The API creates a pending incident from each candidate. It must never convert model confidence directly into an enforcement action.

## Live-camera evolution

For a later one-junction pilot, export the detector to ONNX/TensorRT and run detection close to the RTSP cameras. The edge gateway sends compact incident metadata and selected evidence to Azure IoT Hub; it does not continuously upload every frame. The Flutter review API and incident schema remain unchanged.
