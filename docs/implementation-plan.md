# Bousla — Implementation Plan

This is a proposed plan, not a claim that features are implemented. Read `docs/architecture.md` for the target design. Competition day: **Saturday 28 November 2026**.

Status legend used in progress notes: implemented / partial / planned / unverified.

## Phase 0 — Repository reconnaissance and docs ✅
- Audit done on 22 Nov 2026: repository contained documentation only (no source code, data, backend config or tests).
- Docs moved to the repository root; `project-context.md` updated to the instructor-app + student-web architecture; `architecture.md` written; this plan updated.

## Phase 1 — Course data (Day 1)
- One course: Database Systems.
- About 10 concepts with prerequisite links, 15–20 bilingual multiple-choice questions, a few reviewed resources per concept.
- Format per `architecture.md` §3: language-independent IDs, `{ar, en}` text, options carrying both languages, answer keys in a separate file, provenance and synthetic fields.
- `validate_data.py` (or Dart tests) for unique IDs, missing translations, broken references, answer keys matching option IDs, prerequisite cycles.
Deliverable: dataset + validator + passing checks.

## Phase 2 — Educational engine (Days 1–2, can run in parallel with Phase 3)
Pure Dart in `src/app/lib/core/engine`, no Flutter or Firebase imports.
1. Models.
2. Scoring by option ID.
3. Mastery estimation with insufficient-evidence states (thresholds in `architecture.md` §7; test the boundaries).
4. Prerequisite analysis (possible gaps only; otherwise "needs more evidence").
5. Class aggregates with the small-group threshold.
6. Resource recommendation (preferred language first).
Deliverable: unit tests for boundaries, empty input, unknown IDs, identical results in AR and EN.

## Phase 3 — Instructor session creation + student joining (Days 2–3)
- Flutter project with `flutter_localizations`/`intl`, AR/EN ARB files, bundled Arabic font, locale-driven direction.
- Firebase: Auth (instructor email sign-in, student anonymous), Firestore, Hosting.
- Instructor: sign in → choose course → create session → join code, link and QR (`qr_flutter`).
- Student (web): open link → choose language → answer → responses saved with `display_language`.
- `firebase/firestore.rules` with emulator tests (students cannot read answer keys or other students' data; no writes after close).
Deliverable: a full join-and-answer loop in both languages.

## Phase 4 — Instructor insights (Days 3–4)
- Instructor app runs the engine on live responses (Option A, `architecture.md` §6) and shows aggregate results: participation, concept difficulty, possible prerequisite gaps.
- Empty, small-group, duplicate and late-response states handled.
Deliverable: privacy-conscious live classroom view.

## Phase 5 — Student feedback, recommendations, knowledge map (Days 4–5)
- Instructor releases feedback → per-student feedback documents.
- Student sees mastery states with evidence, cautious wording for possible gaps, and next-step resources in their language.
- Simple knowledge map (concepts with status and prerequisite links; a styled list/tree is enough).
Deliverable: student question-to-insight journey.

## Phase 6 — AI content pipeline (Day 5) — required for the AI criterion
- `generate_bilingual_questions.py`: course material → AI drafts concepts, prerequisites and AR/EN questions as structured JSON.
- Human review step; only approved items enter `data/`; provenance recorded.
- Validator runs on AI output.
- Demo shows: draft → review → approved → used in a live session.
Deliverable: bounded, demonstrable, honest AI functionality.

## Phase 7 — Demo hardening (Day 6)
- Freeze scope; run all tests.
- Synthetic demo data and an offline fallback.
- Full rehearsal on the presentation device and network, in Arabic and English.
- Document limitations honestly.

## Staged after the competition (kept, not removed)
- Persistent learning profiles via optional account linking (`architecture.md` §8).
- Longitudinal progress across sessions.
- Career pathways and skill-gap analysis (`data/careers/backend-developer.json`). A small static demo is possible if time allows.
- Multilingual free-text AI evaluation, only after a rubric, labeled AR/EN/mixed test set, abstention and consistency tests exist.
- Server-side scoring (Option B) for instant feedback.

## Execution discipline
Work in small slices; do not implement all phases in one change. Report what was verified after each slice. Never invent tests, survey findings, sources, or feature status.
