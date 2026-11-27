# Bousla (بوصلة)

An AI-powered educational intelligence platform for Educathon 2026 (Hebron University).

- **Instructor application** (Flutter): create sessions, share a link/QR code, see aggregate classroom insights.
- **Student web portal** (Flutter web): join by link or QR, answer in Arabic or English, get personal feedback and recommendations.
- **Shared backend** (Firebase) and **shared educational engine** (pure Dart).

## Status (26 Nov 2026)

- Live at https://bousla-educathon.web.app (Firebase Spark: Auth, Firestore, Hosting, AI Logic with App Check). Web only; students use the browser on their phones.
- Instructor: review AI-drafted questions (approve / edit / reject, no "approve all"), learning resources (AI describes, the instructor adds the link), create a session with code, link and QR, live class insights (aggregated, hidden under 3 students), close and release feedback, share the feedback link.
- Student: join by code or QR, answer in Arabic or English, personal feedback with next steps and an AI explanation (with a template fallback), knowledge map, optional personal profile by consent (Google sign-in).
- Checks (cloud environment, 26 Nov): rules 46/46 (`firebase/`), engine 118/118 (`src/engine`), app 275/275 and `flutter analyze` clean (`src/app`).
- Not done yet: a measured evaluation of Gemini's explanations against real Gemini (tool ready, run pending), career pathways, longitudinal analytics. Details and limits: `docs/implementation-plan.md`, `docs/ethics-privacy.md`.
- Commands (build, deploy, run, seed, tests): `.\bousla help` on Windows, `./scripts/bousla.sh help` elsewhere; see `firebase/README.md`. Without Firebase settings the app runs in an offline demo mode (in-memory data) and shows a "LOCAL DEMO" corner banner.

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
- `docs/ethics-privacy.md` — privacy principles, what is implemented, known limits.
- `docs/demo-script.md` — draft demo flow.
- `docs/surveys/survey-design.md` — survey overview.
