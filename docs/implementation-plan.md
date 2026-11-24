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

Status (24 Nov): **implemented and verified.** `dart test` in `src/engine` on a developer machine: 54 tests passed with the real `package:test`.

Earlier status (22 Nov): implemented, tests to be confirmed on a developer machine. Items 1–6 done, 54 tests across 5 files (including one that runs the whole engine on the real Database Systems dataset). `dart analyze`: no issues. In the build sandbox pub.dev was unreachable, so the tests ran against a minimal local stand-in for `package:test`; run `dart pub get && dart test` in `src/engine` on a normal machine to confirm with the real package.

## Phase 3 — Instructor session creation + student joining (Days 2–3)
- Flutter project with `flutter_localizations`/`intl`, AR/EN ARB files, bundled Arabic font, locale-driven direction.
- Firebase (Spark): Auth (instructor email sign-in, student anonymous), Firestore, Hosting, App Check.
- Instructor: sign in → choose course → create session from approved questions → join code, link and QR (`qr_flutter`).
- Student (web): open link → choose language → answer → responses saved with `display_language` and `question_version`.
- `firebase/firestore.rules` with emulator tests (students see approved content only, cannot read answer keys or other students' data; no writes after close).
Deliverable: a full join-and-answer loop in both languages.

Status (24 Nov, live): **deployed and used from a real phone.** Real project `bousla-educathon` (Spark), app at https://bousla-educathon.web.app, rules deployed with `firebase deploy`. On the team's Windows machine: instructor account created, course loaded with `.\bousla seed` (10 concepts, 20 questions, 20 answer keys, 10 resources), questions approved in the review screen, session created; a student joined from a phone and answered all questions, the instructor saw the live count. Fixed along the way: a masked API key copied from chat (now `.\bousla check` refuses it), the seed script path on Windows, students restarting at question 1 after a reload (now resume at the first open question), and no endless wait on slow connections (20 s, then a message). A freeze at question 3 seen once on the phone could not be reproduced (Chromium + emulator, 20/20 questions) and did not recur after these fixes. Not yet tested: several phones at once, the venue network, QR code.

Status (24 Nov, Firebase): **Firebase connected; verified on the emulators.** `firebase/firestore.rules` with 27 emulator tests (`cd firebase && npm test`, all pass; a deliberately opened answer-key rule makes them fail). Firestore implementations of `ContentRepository` and `SessionRepository` (`src/app/lib/data/firebase/`), instructor email/password sign-in (`InstructorGate`), anonymous student sign-in, and a course loader (`firebase/tools/seed.mjs`). `flutter analyze` clean, `flutter test` 70/70 (Flutter 3.38.10, includes 22 Firestore repository tests on a fake Firestore). End-to-end on the Auth + Firestore emulators with the built web app in separate browsers: instructor signs in, approves a question in the review screen (saved with reviewer UID), creates a session; two students join by link, one in Arabic and one in English, and answer 5 questions each (10 responses stored with `display_language` 5 ar / 5 en); the instructor sees "2 participants · 10 answers" live; after closing, a new student is told the session is closed. Not yet done: a real Firebase project and Hosting deploy (needs the team's Google account; steps in `firebase/README.md`), QR code, App Check, testing on real phones.

Status (24 Nov): **skeleton compiles and its tests pass.** Platform folders (`web/`, `android/`) committed; `flutter analyze` reported no issues and `flutter test` passed 16 tests on a developer machine (Flutter beta, Dart 3.10). Remaining: Firebase, auth, QR, Firestore rules, insights, feedback.

Earlier status (22 Nov): skeleton written, not yet compiled with Flutter. `src/app` has routes, AR/EN localization with locale-driven direction, repository interfaces with in-memory implementations, and placeholder instructor/student screens (create session with join code and live counts; join by code; answer one question at a time). The data layer (`lib/data`) was analyzed and its 13 tests pass with plain Dart; screens and widget tests still need their first `flutter analyze` / `flutter test` (see `src/app/README.md`). Remaining: Firebase, auth, QR, Firestore rules, insights, feedback.

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

Status (24 Nov, AI level 1): **in-app drafting implemented; not yet run against Gemini.** Review screen → "Draft questions from material (AI)": the instructor picks a PDF/.txt/.md (≤ 15 MB, not stored), chooses 3/5/10, and the app calls Gemini through Firebase AI Logic (`firebase_ai`, Gemini Developer API, structured JSON output). Prompt, JSON schema and output checks are pure Dart in `src/engine/lib/src/ai/question_drafting.dart` (11 tests): concepts limited to approved ones, both languages required (Arabic letters checked), 2–6 options with one correct answer, duplicates and malformed output dropped, option IDs normalised. Passing drafts are saved by `ContentRepository.saveAiDrafts` as `ai_draft` / `pending_review` with answer key, `source_location`, `generated_by` and a `materials` record (name and counts only). Scope of this slice: questions only, linked to existing approved concepts (no new concepts or resources yet; no extracted-text sections). Verified: `dart test` in `src/engine` 69/69, `flutter analyze` clean and `flutter test` 87/87 in the cloud environment (fake generator; the network call itself is not unit-tested). Live check on 24 Nov, after AI Logic was enabled on `bousla-educathon` (first minutes returned PERMISSION_DENIED while permissions propagated): the same instructions and JSON schema as the app, sent over REST with a 3-page text about keys to `gemini-3.5-flash-lite`, returned 3 bilingual drafts (2 foreign key, 1 primary key, with page references and "(Foreign Key)"-style terms), all passing the engine checks. It showed the correct answer always first, so options are now shuffled deterministically and the prompt asks to vary the position. In-app runs later the same day: `gemini-3.5-flash-lite` often answered "high demand" and `gemini-2.5-flash` answered "no longer available to new users … use gemini-3.8-flash", so the app now uses `gemini-3.8-flash` with `gemini-3.5-flash-lite` as fallback (retries on busy). A later in-app run showed the options repeated inside the question text; the engine now removes such a trailing list (and the prompt forbids it), and the review screen lists the latest AI suggestions first under their own heading (file, model, time). One Arabic term was a weak translation ("نزاهة الإشارة" for referential integrity), which is what instructor review is for. The full in-app flow (file picker → Gemini → Firestore) has not yet been run in a browser. Not done: App Check, the ~20-case quality evaluation.

Status (24 Nov): **review screen implemented; `flutter analyze` clean and `flutter test` 37/37 on a developer machine** (data tests + two widget tests for approve / reject / select). The editor screen has no widget test yet. Hide answer language (per question and for all questions; students see the other language): added 24 Nov; `flutter analyze` clean and `flutter test` all passing on a developer machine. `/instructor/review`: approve / edit / reject one question, select several, reject all waiting, optional rejection reason, add questions by hand, AI-draft statistics (approved as is / edited / rejected). Saves to Firestore when Firebase is configured (`FirestoreContentRepository`; question and answer key in one batch), verified on the emulator. Drafting with Gemini is not started.
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
