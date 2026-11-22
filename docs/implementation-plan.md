# Bousla — Implementation Plan

This is a proposed plan, not a claim that features are implemented. Read `docs/architecture.md` for the target design. Competition day: **Saturday 28 November 2026**.

Status legend used in progress notes: implemented / partial / planned / unverified.

## Phase 0 — Repository reconnaissance and docs ✅
- Audit done on 22 Nov 2026: repository contained documentation only (no source code, data, backend config or tests).
- Docs moved to the repository root; `project-context.md` updated to the instructor-app + student-web architecture; `architecture.md` written; this plan updated.
- Decisions recorded: scoring in the instructor app (Option A); AI in two levels; Firebase AI Logic on the Spark plan; no file storage in the MVP.

## Phase 1 — Course data (Day 1)
- One course: Database Systems.
- About 10 concepts with prerequisite links, 15–20 bilingual multiple-choice questions, resources per concept.
- Format per `architecture.md` §3, including `owner_id`, question `version`, provenance with source material links, and resource type/language.
- `validate_data.py` for IDs, translations, references, cycles, answer-key leaks and matching, versions, provenance, resources and materials.
Deliverable: dataset + validator + passing checks.

Status (22 Nov): **partial.** Draft dataset written (10 concepts, 20 questions, 10 practice activities), every item marked `pending_review`. `src/ai/validate_data.py` + 37 unit tests pass (`python -m unittest discover -s src/ai/tests`). Remaining: team review of the content, then set reviewed items to `approved`.

## Phase 2 — Educational engine (Days 1–2)
Pure Dart package `src/engine` (`bousla_engine`), no Flutter or Firebase dependency.
1. Models (matching `architecture.md` §3 and §5).
2. Scoring by option ID and question version.
3. Mastery estimation with insufficient-evidence states (thresholds in `architecture.md` §8; test the boundaries).
4. Prerequisite analysis (possible gaps only; otherwise "needs more evidence").
5. Class aggregates with the small-group threshold.
6. Resource recommendation (approved only; preferred language first).
Deliverable: unit tests for boundaries, empty input, unknown IDs, identical results in AR and EN.

Status (22 Nov): **implemented, tests to be confirmed on a developer machine.** Items 1–6 done, 54 tests across 5 files (including one that runs the whole engine on the real Database Systems dataset). `dart analyze`: no issues. In the build sandbox pub.dev was unreachable, so the tests ran against a minimal local stand-in for `package:test`; run `dart pub get && dart test` in `src/engine` on a normal machine to confirm with the real package.

## Phase 3 — Instructor session creation + student joining (Days 2–3)
- Flutter project with `flutter_localizations`/`intl`, AR/EN ARB files, bundled Arabic font, locale-driven direction.
- Firebase (Spark): Auth (instructor email sign-in, student anonymous), Firestore, Hosting, App Check.
- Instructor: sign in → choose course → create session from approved questions → join code, link and QR (`qr_flutter`).
- Student (web): open link → choose language → answer → responses saved with `display_language` and `question_version`.
- `firebase/firestore.rules` with emulator tests (students see approved content only, cannot read answer keys or other students' data; no writes after close).
Deliverable: a full join-and-answer loop in both languages.

## Phase 4 — Instructor insights (Day 3)
- Instructor app runs the engine on live responses (Option A, `architecture.md` §7) and shows aggregates: participation, concept difficulty, possible prerequisite gaps.
- Empty, small-group, duplicate and late-response states handled.
Deliverable: privacy-conscious live classroom view.

## Phase 5 — Student feedback, recommendations, knowledge map (Day 4)
- Instructor releases feedback → per-student feedback documents.
- Student sees mastery states with evidence, cautious wording for possible gaps, and next-step resources in their language.
- Simple knowledge map (concepts with status and prerequisite links; a styled list/tree is enough).
Deliverable: student question-to-insight journey.

## Phase 6 — AI level 1: content preparation (Days 4–5)
- Instructor picks a PDF/text material → sent to Gemini through Firebase AI Logic (file not stored) → structured JSON drafts with source locations → saved as `pending_review` with a `materials` record.
- Automatic checks (same rules as `validate_data.py`, ported to Dart).
- Review screen: approve / edit / reject each draft; only approved items usable.
- Instructor can also add own resources (links, videos, activities).
- Fallback: if in-app generation is not ready in time, run batch generation offline and demo the review screen, and say so openly.
Deliverable: draft → review → approved → used in a live session.

## Phase 7 — AI level 2: explanations on top of the engine (Day 5)
- Prompt builders and output guards in the engine package (pure Dart, unit-tested): known concepts only, approved resource IDs only, requested language, no definitive diagnostic wording.
- Student: personal explanation + short learning plan. Instructor: suggested teaching action.
- Template fallback on model failure or guard failure; "AI-generated" label next to the evidence.
- Evaluation: ~20 synthetic evidence cases in AR and EN; report the real guard pass rate.
Deliverable: grounded, guarded, measured AI explanations.

## Phase 8 — Demo hardening (Day 6)
- Freeze scope; run all tests.
- Synthetic demo data and an offline fallback (including pre-generated AI outputs if the network fails).
- Full rehearsal on the presentation device and network, in Arabic and English.
- Document limitations honestly.

## If time runs short
Cut from the bottom, not the middle: keep 2 → 3 → 4 → 5 working end to end before polishing 6 and 7. Minimum AI for the demo: level 1 review screen (with offline drafts if needed) + level 2 explanations with guards.

## Staged after the competition (kept, not removed)
- Persistent learning profiles via optional account linking (`architecture.md` §10).
- Longitudinal progress across sessions.
- Career pathways and skill-gap analysis (`data/careers/backend-developer.json`). A small static demo is possible if time allows.
- Multilingual free-text AI evaluation, only after a rubric, labeled AR/EN/mixed test set, abstention and consistency tests exist.
- Storing uploaded files and file resources (Cloud Storage, Blaze plan).
- Server-side scoring (Option B) for instant feedback.

## Execution discipline
Work in small slices; do not implement all phases in one change. Report what was verified after each slice. Never invent tests, survey findings, sources, or feature status.
