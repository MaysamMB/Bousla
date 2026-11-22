# Bousla (بوصلة)

An AI-powered educational intelligence platform for Educathon 2026 (Hebron University).

- **Instructor application** (Flutter): create sessions, share a link/QR code, see aggregate classroom insights.
- **Student web portal** (Flutter web): join by link or QR, answer in Arabic or English, get personal feedback and recommendations.
- **Shared backend** (Firebase) and **shared educational engine** (pure Dart).

## Status (22 Nov 2026)

- Draft bilingual Database Systems dataset (`data/courses/database-systems`), pending human review.
- Data validator (`src/ai/validate_data.py`).
- Deterministic educational engine (`src/engine`).
- Flutter app skeleton (`src/app`): routes, Arabic/English, in-memory data, placeholder screens. Not yet connected to Firebase; see `src/app/README.md` for first-time setup.

## Running the checks

```bash
# Data validation (Python 3.9+, no packages needed)
python src/ai/validate_data.py data/courses/database-systems
python -m unittest discover -s src/ai/tests

# Engine (Dart 3.5+ or Flutter's bundled Dart)
cd src/engine
dart pub get
dart test
```

## Documentation

- `CLAUDE.md` — working instructions for Claude Code.
- `docs/project-context.md` — product vision and requirements.
- `docs/architecture.md` — target technical design.
- `docs/implementation-plan.md` — phased plan to the competition.
- `docs/ethics-privacy.md` — privacy principles.
- `docs/demo-script.md` — draft demo flow.
- `docs/surveys/survey-design.md` — survey overview.
