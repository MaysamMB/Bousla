# Bousla (بوصلة)

An AI-powered educational intelligence platform for Educathon 2026 (Hebron University).

- **Instructor application** (Flutter): create sessions, share a link/QR code, see aggregate classroom insights.
- **Student web portal** (Flutter web): join by link or QR, answer in Arabic or English, get personal feedback and recommendations.
- **Shared backend** (Firebase) and **shared educational engine** (pure Dart).

## Status (26 Nov 2026 — instructor QA update)

- Live at https://bousla-educathon.web.app (Firebase Spark: Auth, Firestore, Hosting). Instructor signs in, reviews questions, creates a session; students join by code or link from their phones and answer in Arabic or English; the instructor sees live counts. Verified from a real phone.
- Security rules with emulator tests (`firebase/`), deterministic engine (`src/engine`), Flutter app (`src/app`).
- Draft bilingual Database Systems dataset (`data/courses/database-systems`), pending team review; validator `src/ai/validate_data.py`.
- Classroom insights, QR joining, teaching actions, presentation mode, past sessions and session renaming are implemented. Student feedback, knowledge maps and AI drafting/explanations are also implemented; see the implementation plan for their separately recorded verification status.
- Instructor rehearsal (26 Nov): 3 participant records, 49 answers, 6 of 10 concepts displayed and 4 suppressed. Presentation mode was observed on a computer; session closure/history/rename were reported complete by the tester.
- Targeted local Flutter tests: **10/10 passed** (3 prerequisite rehearsal tests, 4 mocked teaching-strategy tests, 3 presentation-layout tests). The live prerequisite signal, live Gemini teaching tactic, and physical projector remain to be verified. The results are not evidence of real learning gains.
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
- `docs/ethics-privacy.md` — privacy principles.
- `docs/demo-script.md` — demo flow and rehearsal status.
- [Instructor QA and rehearsal log](docs/qa/Bousla_QA_2026-11-26.md) — observed results, targeted tests and outstanding live checks.
- `docs/surveys/survey-design.md` — survey overview.
