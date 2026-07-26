# Architecture

```text
Flutter operator app
        |
        | HTTPS + Entra token
        v
API Management -> Container Apps / FastAPI
        |                    |
        |                    +-> Cosmos DB (jobs, incidents, reviews)
        |                    +-> SignalR (progress and alerts)
        v
Private Blob Storage -> Azure ML batch inference
                              |
                              +-> detector + tracker + temporal rules
                              +-> Azure Vision OCR on selected plate crops
                              +-> Face Detection on evidence keyframes only
                              v
                       Private evidence container
```

The cloud workflow is asynchronous because a recorded clip may take longer than a mobile request timeout. Locally, a FastAPI background task runs real ONNX inference and implements the same state transitions in one process. The Azure deployment should move that worker to Azure ML or Container Apps Jobs and use durable orchestration plus a persistent Cosmos repository.

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
