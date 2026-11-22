# Bousla — Architecture

> Status (22 Nov 2026): the application is **not implemented yet**. Implemented so far: a draft bilingual Database Systems dataset (`data/courses/database-systems`) and its validator (`src/ai/validate_data.py`, with tests). This is the agreed target design; update it when the implementation differs.

## 1. Components

| Component | Technology | Users |
|---|---|---|
| Instructor application | Flutter (web, optionally Android) | Instructors |
| Student web portal | Flutter web, same codebase, separate routes | Students (no install; link or QR) |
| Shared backend | Firebase on the no-cost Spark plan: Authentication, Cloud Firestore, Hosting, App Check | Both |
| Educational intelligence engine | Pure Dart library inside the app (`lib/core/engine`) | Used by the instructor app |
| Generative AI | Gemini through **Firebase AI Logic** (called from the instructor app; key stays on Google's proxy, protected by App Check) | Instructor app |
| Offline content tools | Python scripts in `src/ai` (validation; batch generation fallback) | Team |

One Flutter project serves both roles:
- `/join/:code` → student portal
- `/instructor/...` → instructor application

Reason: one codebase, shared models and engine, one deployment.

**Plan constraint:** Cloud Storage for Firebase requires the paid Blaze plan, so the MVP does not store uploaded files (see §4).

## 2. Target repository layout

```
Bousla/
├── CLAUDE.md, README.md
├── docs/                      project-context, architecture, implementation-plan, ethics-privacy, demo-script, surveys/
├── data/
│   ├── courses/database-systems/
│   │   ├── course.json        course metadata, owner_id
│   │   ├── concepts.json      concepts + prerequisite links (bilingual)
│   │   ├── questions.json     bilingual questions WITHOUT correct answers
│   │   ├── answer_keys.json   correct option IDs (never bundled into the web app)
│   │   ├── resources.json     learning resources (bilingual)
│   │   └── materials.json     optional: metadata of source materials content was generated from
│   ├── careers/backend-developer.json
│   └── demo/                  synthetic responses, labeled synthetic
├── src/
│   ├── app/                   Flutter project
│   │   ├── lib/core/models/
│   │   ├── lib/core/engine/   pure Dart: must NOT import Flutter or Firebase
│   │   ├── lib/core/ai/       prompt builders + output guards (pure Dart, testable)
│   │   ├── lib/data/          repositories/, services/ (Firebase, Firebase AI Logic)
│   │   ├── lib/features/instructor/   dashboard, courses, materials, content_review, sessions, live_insights
│   │   ├── lib/features/student_web/  join_session, answering, feedback, knowledge_map, learning_profile
│   │   ├── lib/shared/        localization/, widgets/
│   │   └── test/
│   └── ai/                    validate_data.py, tests/, prompts/, batch generation fallback (later)
└── firebase/firestore.rules
```

Rule: `lib/core/engine` and `lib/core/ai` depend only on `lib/core/models` and the Dart SDK. The network call to Gemini lives in `lib/data/services`, so prompts and guards can be unit-tested without the network.

## 3. Content model

All IDs are language-independent. Every option carries both languages, so the two languages cannot drift apart in count, order or IDs.

### Course
```json
{
  "id": "database_systems",
  "name": { "ar": "أنظمة قواعد البيانات", "en": "Database Systems" },
  "owner_id": null,
  "languages": ["ar", "en"]
}
```
`owner_id` is the instructor's Firebase UID. It is `null` only in seed files; in Firestore it decides who may edit the course.

### Concept
```json
{
  "id": "foreign_key",
  "name": { "ar": "المفتاح الخارجي", "en": "Foreign Key" },
  "prerequisites": ["primary_key"],
  "provenance": { "...": "see below" }
}
```

### Question
```json
{
  "id": "db_fk_001",
  "version": 1,
  "concept_ids": ["foreign_key"],
  "type": "multiple_choice",
  "difficulty": "basic",
  "prompt": { "ar": "ما وظيفة المفتاح الخارجي؟", "en": "What is the purpose of a foreign key?" },
  "options": [
    { "id": "a", "text": { "ar": "ربط الجداول المرتبطة", "en": "Connect related tables" } },
    { "id": "b", "text": { "ar": "تكرار السجلات", "en": "Duplicate records" } }
  ],
  "provenance": { "...": "see below" },
  "synthetic": false
}
```
Answer keys are stored separately: `{ "db_fk_001": { "correct_option_id": "a" } }`.

### Resource
```json
{
  "id": "res_fk_video",
  "concept_ids": ["foreign_key"],
  "type": "video",
  "title": { "ar": "شرح المفتاح الخارجي", "en": "Foreign keys explained" },
  "description": { "ar": "...", "en": "..." },
  "url": "https://...",
  "storage_path": null,
  "language": "ar",
  "added_by": "<instructor uid or 'team'>",
  "provenance": { "...": "see below" }
}
```
- `type`: `activity` (text only), `link`, `video` (need `url`), `file` (needs `storage_path`; requires Cloud Storage → Blaze plan, so not in the MVP).
- `language`: `ar`, `en` or `both`. The recommender prefers the student's language and falls back to the other.

### Provenance (on every concept, question and resource)
```json
{
  "source": "ai_draft",
  "status": "pending_review",
  "reviewed_by": null,
  "source_material_id": "mat_lecture_03",
  "source_location": "pages 4-6"
}
```
- `source`: `ai_draft`, `instructor` (written by hand) or `team` (seed content).
- `status`: `pending_review`, `approved` or `rejected`.
- `source_material_id` / `source_location`: where an AI draft came from, so the instructor can check it quickly. `null` when the content was not generated from an uploaded material.

### Material (metadata only in the MVP)
```json
{
  "id": "mat_lecture_03",
  "title": "Lecture 3 — Keys",
  "file_name": "lecture03.pdf",
  "uploaded_by": "<instructor uid>",
  "status": "ready_for_review"
}
```
`status`: `processing`, `ready_for_review`, `failed`.

Validation (`validate_data.py`, mirrored later in Dart): unique IDs; non-empty `ar`/`en`; Arabic fields contain Arabic letters; valid references and no prerequisite cycles; no answers inside questions; one matching key per question; `version` ≥ 1; allowed `type`/`language`/`source`/`status` values; resource URL/path rules; `source_material_id` refers to a listed material.

**Public repository note:** this GitHub repository is public, so committed `answer_keys.json` is publicly readable. Acceptable only for demo questions. For real use, keep keys out of the repository and load them into Firestore privately.

## 4. Content lifecycle (instructor-owned content)

1. **Upload:** the instructor picks a PDF/text file in the instructor app. In the MVP the file stays on the instructor's device; it is sent directly to Gemini through Firebase AI Logic and is **not stored** (no Cloud Storage on Spark). Only a `materials` metadata document is saved.
2. **AI drafting (AI level 1):** Gemini returns structured JSON: concepts, prerequisite links, bilingual questions with a proposed answer, and resource suggestions, each with its source location. Everything is saved as `pending_review`.
3. **Automatic checks:** the same rules as `validate_data.py` run on the drafts. Failing drafts are flagged, not saved as approved.
4. **Human review:** the instructor approves, edits or rejects each item in a review screen. Only `approved` content can be used in sessions or shown to students.
5. **Use:** sessions reference approved question IDs and versions.

**Versioning:** a question version that has been used in a session is never edited in place. Editing creates `version + 1`; responses store the version they answered, so old evidence still matches the question it was given for.

Uploading the instructor's own resources (links, videos, activities) follows steps 4–5 with `source: "instructor"`.

## 5. Responses

One document per participant per question:

```json
{
  "question_id": "db_fk_001",
  "question_version": 1,
  "selected_option_id": "a",
  "display_language": "ar",
  "free_text": null,
  "submitted_at": "<server timestamp>"
}
```

- Scoring compares `selected_option_id` with the key for that question version, never option text, so results are identical in Arabic and English.
- `free_text` stores the student's original wording unchanged. It is not auto-scored in the MVP.

## 6. Firestore collections

| Path | Written by | Read by |
|---|---|---|
| `courses/{courseId}` | course owner | owner; students in a session of this course (public fields) |
| `courses/{courseId}/materials/{materialId}` | owner | owner |
| `courses/{courseId}/concepts`, `questions`, `resources` | owner (drafts and approvals) | owner: all; students: **only `approved` items** |
| `courses/{courseId}/answer_keys/{questionId}` | owner | **owner only** |
| `sessions/{sessionId}` | owner | owner; students who know the code can read public fields |
| `sessions/{sessionId}/participants/{uid}` | that student | that student; owner sees count only in the UI |
| `sessions/{sessionId}/responses/{uid}_{questionId}` | that student, only while the session is open | owner (for scoring) |
| `sessions/{sessionId}/aggregates/summary` | owner's app (engine output) | owner |
| `sessions/{sessionId}/feedback/{uid}` | owner's app (engine + AI level 2 output) | that student only, and only if feedback is enabled |
| `profiles/{uid}` | that student (after identity linking) | that student only |

All of these permissions are enforced in `firebase/firestore.rules` and tested with the Firebase emulator. Hiding things in the UI is not authorization.

## 7. Where scoring runs

**MVP decision (Option A, confirmed by the team on 22 Nov 2026):** the engine runs in the **instructor app**.

1. Students submit option IDs only. They never receive answer keys.
2. The instructor app reads responses and keys, runs the engine, and writes `aggregates/summary` live.
3. When the instructor ends the session (or presses "release feedback"), the app writes one `feedback/{uid}` document per student.

Trade-offs: free, simple, no answer-key exposure; but personal feedback appears after release, and the instructor app must be open during the session.

**Later option (B):** server-side scoring (Cloud Functions / Cloud Run, Blaze plan) for instant feedback. The engine's no-Flutter/no-Firebase rule keeps this possible.

## 8. Educational engine (deterministic)

Pure functions over models. Starter thresholds are provisional, configurable, and not scientifically validated:

| State | Rule |
|---|---|
| Insufficient evidence | fewer than 2 responses for the concept |
| Possible difficulty | ≥ 2 responses and accuracy < 50% |
| Demonstrated mastery | ≥ 3 responses and accuracy ≥ 75% |
| Emerging / uncertain | anything else |

Modules: `question_concept_mapper`, `mastery_estimator`, `prerequisite_analyzer` (flags a prerequisite as a *possible* contributing gap only when the prerequisite itself shows difficulty or insufficient evidence; otherwise suggests more assessment), `class_insights`, `learning_recommender`, `career_gap_analyzer` (later).

Every output carries its evidence (number of responses, accuracy) so the UI can show *why*. AI never changes these results.

## 9. AI in two levels

### Level 1 — AI in content preparation
See §4. Gemini drafts concepts, prerequisite links, bilingual questions and resources from the instructor's material, with source locations. Deterministic checks and human review decide what is used.

### Level 2 — AI on top of the engine (inside the app)
The engine produces verified, structured evidence. Gemini turns it into language:
- **Student:** a short personal explanation and learning plan, in the student's language.
- **Instructor:** a suggested teaching action based on class aggregates (e.g. which prerequisite to revisit).

**Input given to the model:** only structured evidence: concept IDs and names, mastery states, response counts, prerequisite links, and IDs/titles of approved resources. **Never** names, UIDs, nicknames or raw responses.

**Output guards** (pure Dart in `lib/core/ai`, unit-tested):
- Mentions only concepts present in the evidence.
- Recommends only approved resource IDs from the input.
- Written in the requested language.
- No definitive diagnostic wording ("you have a gap" → "may need review").
- If the model fails, times out or a guard fails → fall back to a deterministic template message.

**Transparency:** AI text is labeled "AI-generated" and shown next to the evidence it was based on. The instructor can turn AI explanations off per session.

**Evaluation before the demo:** run the level-2 generator on about 20 synthetic evidence cases in both languages and report the guard pass rate. Report the real number, whatever it is.

### Later
| Component | Condition |
|---|---|
| Career skill mapping | small static map for one role first |
| Free-text answer evaluation | only after a bilingual rubric, a labeled AR/EN/mixed test set, abstention when uncertain, and consistency tests exist |
| Storing uploaded files | needs Cloud Storage (Blaze plan) |

AI never scores multiple-choice answers and never overrides engine results.

## 10. Identity

1. **Session participation (MVP):** students join with Firebase Anonymous Authentication. The anonymous UID identifies a participant within a session only. It is tied to a browser, not a person, and must not be presented as a persistent student identity.
2. **Optional persistent profile (staged):** a "Save my progress" action links the anonymous account to a real sign-in (university email link or Google) using Firebase account linking (`linkWithCredential`). The same UID is kept, so the session's data moves into the profile. Only then is longitudinal tracking claimed.
3. Optional nickname only; no real name required to join.
4. The QR code / join link contains only the session code, never a personal token.

## 11. Localization

- `flutter_localizations` + `intl` with ARB files (`app_ar.arb`, `app_en.arb`) for UI strings.
- Content text comes from the `{ar, en}` fields in data.
- Layout direction follows the active locale (no hard-coded RTL/LTR).
- Bundle an Arabic-capable font with the app; do not download fonts at runtime (venue network may be unreliable).
- Test mixed Arabic/English technical terms, e.g. "المفتاح الأساسي (Primary Key)".

## 12. Privacy controls

- Instructor views are aggregate only by default.
- Concept-level breakdowns are hidden when fewer than **5** participants answered (configurable).
- Join codes: random, at least 6 characters; sessions have an open/closed state; responses are rejected after closing.
- No AI API keys in client code: Gemini is reached only through Firebase AI Logic with App Check enforced.
- No personal identifiers are sent to the model (§9).
- Check the Gemini API terms for how the chosen tier may use submitted content before sending real course materials or real student evidence; use synthetic data for the demo.
- Synthetic demo data is labeled `"synthetic": true`.
