# Bousla (بوصلة)

An AI-powered educational intelligence platform for Educathon 2026 (Hebron University).

- **Instructor application** (Flutter): create sessions, share a link/QR code, see aggregate classroom insights.
- **Student web portal** (Flutter web): join by link or QR, answer in Arabic or English, get personal feedback and recommendations.
- **Shared backend** (Firebase) and **shared educational engine** (pure Dart).

## Status (26 Nov 2026)

- Live at https://bousla-educathon.web.app (Firebase Spark: Auth, Firestore, Hosting, AI Logic with App Check). Web only; students use the browser on their phones.
- Instructor: review AI-drafted questions (approve / edit / reject, no "approve all"), learning resources (AI describes, the instructor adds the link), create a session with code, link and QR, live class insights (aggregated, hidden under 3 students), close and release feedback, share the feedback link.
- Student: join by code or QR, answer in Arabic or English, personal feedback with next steps and an AI explanation (with a template fallback), knowledge map, optional personal profile by consent (Google sign-in).
- Instructor rehearsal (26 Nov): 3 participant records, 49 answers, 6 of 10 concepts displayed and 4 suppressed. Presentation mode was observed on a computer; session closure/history/rename were reported complete by the tester.
- Targeted local Flutter tests: **10/10 passed** (3 prerequisite rehearsal tests, 4 mocked teaching-strategy tests, 3 presentation-layout tests). The live prerequisite signal, live Gemini teaching tactic, and physical projector remain to be verified. The results are not evidence of real learning gains.
- Checks (cloud environment, 27 Nov, after merging Yasmeen's QA branch): rules 46/46 (`firebase/`), engine 126/126 (`src/engine`), app 297/297 and `flutter analyze` clean (`src/app`).
- Gemini explanation evaluation: one real run on 20 synthetic profiles, 20 of 20 passed the five guards (26 Nov; `src/engine/gemini_eval_report/`).
- Career path (preview, from "My profile"): a chosen job's ESCO skills compared with the student's saved evidence, plus an early sample of local job adverts (shown from 10 adverts). "Add a course from outside Bousla" is an interface preview only (nothing uploaded or saved). Data: `src/app/assets/careers/`, `data/careers/`.
- Not done yet: outline topic extraction and the AI self-check for outside courses, a cross-checked local-adverts sample, longitudinal analytics. Details and limits: `docs/implementation-plan.md`, `docs/ethics-privacy.md`.
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
- `docs/demo-script.md` — demo flow and rehearsal status.
- [Instructor QA and rehearsal log](docs/qa/Bousla_QA_2026-11-26.md) — observed results, targeted tests and outstanding live checks.
- `docs/surveys/survey-design.md` — survey overview.
