# Bousla — Architecture

> Status (22 Nov 2026): **nothing in this document is implemented yet.** The repository contains documentation only. This is the agreed target design; update it when the implementation differs.

## 1. Components

| Component | Technology | Users |
|---|---|---|
| Instructor application | Flutter (web, optionally Android) | Instructors |
| Student web portal | Flutter web, same codebase, separate routes | Students (no install; link or QR) |
| Shared backend | Firebase: Authentication, Cloud Firestore, Hosting | Both |
| Educational intelligence engine | Pure Dart library inside the app (`lib/core/engine`) | Used by the instructor app |
| AI content tools | Python scripts (`src/ai`), run offline by the team | Team / instructors |

One Flutter project serves both roles:
- `/join/:code` → student portal
- `/instructor/...` → instructor application

Reason: one codebase, shared models and engine, one deployment. Two separate apps would double the work with no benefit for the MVP.

## 2. Target repository layout

```
Bousla/
├── CLAUDE.md, README.md
├── docs/                      project-context, architecture, implementation-plan, ethics-privacy, demo-script, surveys/
├── data/
│   ├── courses/database-systems/
│   │   ├── concepts.json      concepts + prerequisite links (bilingual)
│   │   ├── questions.json     bilingual questions WITHOUT correct answers
│   │   ├── answer_keys.json   correct option IDs (never bundled into the web app)
│   │   └── resources.json     reviewed learning resources (bilingual)
│   ├── careers/backend-developer.json
│   └── demo/                  synthetic responses, labeled synthetic
├── src/
│   ├── app/                   Flutter project
│   │   ├── lib/core/models/
│   │   ├── lib/core/engine/   pure Dart: must NOT import Flutter or Firebase
│   │   ├── lib/data/          repositories/, services/ (Firebase access)
│   │   ├── lib/features/instructor/   dashboard, courses, sessions, question_bank, live_insights
│   │   ├── lib/features/student_web/  join_session, answering, feedback, knowledge_map, learning_profile
│   │   ├── lib/shared/        localization/, widgets/
│   │   └── test/
│   └── ai/                    prompts/, generate_bilingual_questions.py, validate_data.py, tests/ (others later)
└── firebase/firestore.rules
```

Rule: `lib/core/engine` depends only on `lib/core/models` and the Dart SDK. This keeps it testable and lets it move to a server later without changes.

## 3. Bilingual content model

All IDs are language-independent. Every option carries both languages, so the two languages cannot drift apart in count, order or IDs.

```json
{
  "id": "db_fk_001",
  "concept_ids": ["foreign_key"],
  "difficulty": "basic",
  "prompt": {
    "ar": "ما وظيفة المفتاح الخارجي؟",
    "en": "What is the purpose of a foreign key?"
  },
  "options": [
    { "id": "a", "text": { "ar": "ربط الجداول المرتبطة", "en": "Connect related tables" } },
    { "id": "b", "text": { "ar": "تكرار السجلات", "en": "Duplicate records" } }
  ],
  "provenance": { "source": "ai_draft", "reviewed_by": "team", "status": "approved" },
  "synthetic": false
}
```

Answer keys are stored separately:

```json
{ "db_fk_001": { "correct_option_id": "a" } }
```

Concepts:

```json
{
  "id": "foreign_key",
  "name": { "ar": "المفتاح الخارجي", "en": "Foreign Key" },
  "prerequisites": ["primary_key", "relational_model"]
}
```

Validation (`validate_data.py` and/or Dart tests): unique IDs, both `ar` and `en` present and non-empty, every `concept_ids` / `prerequisites` reference exists, every question has exactly one answer key that matches an option ID, no prerequisite cycles.

**Public repository note:** this GitHub repository is public, so `answer_keys.json` committed here is publicly readable. For the competition this is acceptable only with demo questions. For real use, keep keys out of the repository and load them into Firestore through a private seed step.

## 4. Responses

One document per participant per question:

```json
{
  "question_id": "db_fk_001",
  "selected_option_id": "a",
  "display_language": "ar",
  "free_text": null,
  "submitted_at": "<server timestamp>"
}
```

- Scoring compares `selected_option_id` to the key, never option text, so results are identical in Arabic and English.
- `free_text` stores the student's original wording unchanged. It is not auto-scored in the MVP.

## 5. Firestore collections

| Path | Written by | Read by |
|---|---|---|
| `courses/{courseId}` + `concepts`, `questions`, `resources` | seed script / instructor | everyone signed in |
| `courses/{courseId}/answer_keys/{questionId}` | seed script / instructor | **instructor only** |
| `sessions/{sessionId}` | instructor (owner) | owner; students who know the code can read public fields |
| `sessions/{sessionId}/participants/{uid}` | that student | that student; owner sees count only in the UI |
| `sessions/{sessionId}/responses/{uid}_{questionId}` | that student, only while the session is open | owner (for scoring) |
| `sessions/{sessionId}/aggregates/summary` | instructor app (engine output) | owner |
| `sessions/{sessionId}/feedback/{uid}` | instructor app (engine output) | that student only, and only if feedback is enabled |
| `profiles/{uid}` | that student (after identity linking) | that student only |

All of these permissions are enforced in `firebase/firestore.rules` and tested with the Firebase emulator. Hiding things in the UI is not authorization.

## 6. Where scoring runs

**MVP decision (Option A, pending team confirmation):** the engine runs in the **instructor app**.

1. Students submit option IDs only. They never receive answer keys.
2. The instructor app, which is allowed to read the keys, reads responses, runs the engine, and writes `aggregates/summary` live.
3. When the instructor ends the session (or presses "release feedback"), the app writes one `feedback/{uid}` document per student.

Trade-offs: free (no paid Firebase plan), simple, no answer-key exposure. But personal feedback appears after release rather than instantly, and the instructor app must be open during the session.

**Later option (B):** move scoring to a server (Cloud Functions or a Dart server on Cloud Run) for instant feedback without the instructor app. This needs the paid Blaze plan. The engine's no-Flutter/no-Firebase rule keeps this move possible.

## 7. Educational engine

Pure functions over models. Starter thresholds are provisional, configurable, and not scientifically validated:

| State | Rule |
|---|---|
| Insufficient evidence | fewer than 2 responses for the concept |
| Possible difficulty | ≥ 2 responses and accuracy < 50% |
| Demonstrated mastery | ≥ 3 responses and accuracy ≥ 75% |
| Emerging / uncertain | anything else |

Modules: `question_concept_mapper`, `mastery_estimator`, `prerequisite_analyzer` (flags a prerequisite as a *possible* contributing gap only when the prerequisite itself shows difficulty or insufficient evidence; otherwise suggests more assessment), `class_insights`, `learning_recommender`, `career_gap_analyzer` (later).

Every output carries its evidence (number of responses, accuracy) so the UI can show *why*.

## 8. Identity

1. **Session participation (MVP):** students join with Firebase Anonymous Authentication. The anonymous UID identifies a participant within a session only. It is tied to a browser, not a person, and must not be presented as a persistent student identity.
2. **Optional persistent profile (staged):** a "Save my progress" action links the anonymous account to a real sign-in (university email link or Google) using Firebase account linking (`linkWithCredential`). The same UID is kept, so the session's data moves into the profile. Only then is longitudinal tracking claimed.
3. Optional nickname only; no real name required to join.
4. The QR code / join link contains only the session code, never a personal token.

## 9. Localization

- `flutter_localizations` + `intl` with ARB files (`app_ar.arb`, `app_en.arb`) for UI strings.
- Content text comes from the `{ar, en}` fields in data.
- Layout direction follows the active locale (no hard-coded RTL/LTR).
- Bundle an Arabic-capable font with the app; do not download fonts at runtime (venue network may be unreliable).
- Test mixed Arabic/English technical terms, e.g. "المفتاح الأساسي (Primary Key)".

## 10. Privacy controls

- Instructor views are aggregate only by default.
- Concept-level breakdowns are hidden when fewer than **5** participants answered (configurable).
- Join codes: random, at least 6 characters; sessions have an open/closed state; responses are rejected after closing.
- No AI API keys in client code. AI tools run offline in `src/ai` with keys in local environment variables.
- Synthetic demo data is labeled `"synthetic": true`.

## 11. AI components

| Component | Status | Role |
|---|---|---|
| Bilingual question and concept drafting (`generate_bilingual_questions.py`) | planned, MVP | AI drafts concepts, prerequisite links and AR/EN questions from course material; humans review; approved items get `provenance.status = "approved"` |
| Data validation (`validate_data.py`) | planned, MVP | Deterministic checks (not AI) |
| Personalized explanations | optional | Must use only approved content and engine results |
| Career skill mapping | later | |
| Free-text answer evaluation | later | Only after a bilingual rubric, a labeled AR/EN/mixed test set, abstention when uncertain, and consistency tests exist |

AI never scores multiple-choice answers and never overrides engine results.
