# Contributing to STMS

Thank you for improving STMS. Traffic-safety software needs careful engineering, reproducible testing and explicit uncertainty.

## Development workflow

1. Create a focused branch from `main`.
2. Keep credentials, footage, evidence, model binaries and personal data outside Git.
3. Format and test the affected stack.
4. Update documentation when behavior, configuration or API contracts change.
5. Open a pull request describing the problem, approach, validation and safety impact.

## Required checks

Flutter:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Backend:

```powershell
cd backend
python -m pytest -q
```

## Detection and rule changes

- Add tests for false positives as well as expected detections.
- Require temporal evidence for violations that occur across frames.
- Do not infer identity, ownership or protected/sensitive attributes.
- Keep model output advisory and preserve human review.
- Document calibration assumptions and the representative data used for evaluation.
- Never weaken privacy controls to simplify a demonstration.

## Pull requests

Include:

- a concise description of the user-visible change;
- screenshots for UI changes, using synthetic or anonymized data;
- test commands and results;
- configuration or migration steps;
- known limitations and possible false-positive impact.

Do not attach real licence plates, faces, credentials or private road-camera footage to a public issue or pull request.
