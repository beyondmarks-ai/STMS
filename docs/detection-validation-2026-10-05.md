# Uploaded-video detection investigation, 5 October 2026

The earlier phone test verified upload, job completion and automatic refresh. It did not establish violation-detection accuracy.

## Reproduction

The AWS worker ran task revision 8 with real inference enabled and the original image's analyzer. Its startup overrides changed database/storage code, not the analyzer. The local reproduction used that image's analyzer and the same model files, with the default two inference samples per second and 0.30 detector threshold. Cloud visual enrichment was not used in the local runs.

| Video | Samples | Baseline incidents | Incidents after class-aware NMS |
| --- | ---: | ---: | ---: |
| `VID-20261005-WA0001.mp4` (40.74 seconds, ferry unloading) | 81 | 0 | 0 |
| `14571032_3840_2160_60fps.mp4` (7.77 seconds, road traffic) | 16 | 7 no-helmet candidates | 7 no-helmet candidates |

The ferry clip produced five motorcycle detections across the 81 sampled frames, split into four tracks. Three helmet detections and no bare-head detections were produced. No-helmet alerts require at least two bare-head detections within one vehicle track. This explains why that rule generated no alerts; it does not prove that every vehicle or violation was recognized.

The road-traffic clip produced 76 motorcycle detections and 54 bare-head detections before the fix, and 78 motorcycle detections and 56 bare-head detections afterwards. These counts are observations across frames, not distinct vehicles. The baseline seven alerts also matched the previously stored AWS job `JOB-52026FFE`. Its evidence includes a visible rider without a helmet. Candidate count is not a measured precision or recall score; human review is still required.

## Correction

Raw YOLO outputs previously used non-maximum suppression across all classes. A high-confidence person could suppress an overlapping motorcycle. NMS now removes duplicate boxes within each class, preserving overlapping objects of different classes. Regression tests cover overlapping riders/motorcycles, same-class duplicates, separate vehicles, confidence filtering and requested-label filtering. The focused detector, enrichment and rule suite passed all seven tests.

This correction improves object retention in the road clip but does not change the ferry clip's result. It must not be presented as fixing every false negative.

## Production verification

The detector correction was deployed as AWS worker task revision 9, preserving the existing image, configuration and startup overrides. A fresh upload of the road clip, named `qa-helmet-detection.mp4` with camera `QA detector validation`, produced job `JOB-95CAF0D0`. It completed at 100% with seven no-helmet incident records and no job error. Image evidence was successfully retrieved from the API. The phone had disconnected from ADB by this stage, so this final check used the production API rather than a second phone UI upload.

## Missing coverage

The uploaded-video analyzer has no accident/collision detector and no phone-use violation rule. A generic object detector can recognize a vehicle without understanding a crash. Accident coverage requires a separate temporal detector or validated event-recognition pipeline, incident schema/UI support, and positive and negative validation clips.

Wrong-side detection is disabled by default until direction calibration is enabled. Triple-riding detection depends on recognizing and consistently associating three people with one motorcycle. Distance, occlusion, missed vehicles and track fragmentation remain limitations.

Completion and a zero incident count must not be used as evidence that a scene was safe or violation-free. This investigation is a two-clip functional check, not a labeled accuracy benchmark.
