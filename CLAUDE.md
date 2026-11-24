# CLAUDE.md — Bousla

## Project Identity

Bousla is an AI-powered educational intelligence platform.

The product has:
1. An instructor application.
2. A responsive student web portal.
3. One shared backend.
4. One shared educational intelligence engine.

Students do not install a separate native application. They join assessments using a web link or QR code.

Read `docs/project-context.md`, `docs/architecture.md`, and `docs/implementation-plan.md` before major changes.

## Core Principles

1. Inspect existing code before making changes.
2. Preserve working functionality.
3. Avoid unnecessary rewrites.
4. Implement features incrementally.
5. Keep educational logic independent of UI and Firebase.
6. Separate observed evidence from estimates and AI interpretations.
7. Never present uncertain learning estimates as definitive diagnoses.
8. Human-review AI-generated educational content.
9. Enforce privacy through backend authorization.
10. Never expose credentials or answer keys unnecessarily.

## Product Architecture

### Instructor
- Dashboard
- Course management
- Session creation
- Question management
- Join link and QR generation
- Live classroom insights

### Student Web Portal
- Join session
- Answer questions
- View personal feedback
- Knowledge map
- Learning profile
- Recommendations

## Arabic and English

Arabic and English support is mandatory.

- Support RTL for Arabic.
- Support LTR for English.
- Provide bilingual question content.
- Use stable language-independent question and concept IDs.
- Store the language displayed to the student.
- Preserve original free-text responses.
- Do not use naive exact string matching for multilingual answers.
- Use bilingual evaluation rubrics for AI-based free-text assessment.
- Include uncertainty and abstention in AI evaluation.
- Test Arabic, English, and mixed technical terminology.

## Educational Engine

The engine must support:

- Question-to-concept mapping.
- Mastery estimation.
- Insufficient-evidence states.
- Prerequisite analysis.
- Classroom insights.
- Personalized recommendations.
- Career skill-gap analysis.

Keep the engine deterministic and testable wherever possible.

AI-generated interpretations must never override verified scoring rules.

## Student Identity and Privacy

- Session-only participation is different from persistent learning history.
- Do not claim longitudinal tracking without reliable identity linking.
- Protect personal learning profiles.
- Instructor views should be aggregated by default.
- Consider small-group privacy risks.
- Backend rules must enforce access permissions.
- Personal access links must be treated as sensitive credentials.

## Development Workflow

For every task:

1. Inspect relevant files.
2. Explain the existing implementation.
3. Identify affected files.
4. Propose a focused implementation plan.
5. Implement one coherent feature.
6. Add tests.
7. Run applicable checks.
8. Report verified results and remaining limitations.

## Scope Priority

Prioritize:

1. Instructor session creation.
2. Student web joining.
3. Arabic/English question answering.
4. Response collection.
5. Concept mapping.
6. Mastery estimation.
7. Aggregate classroom insights.
8. Student feedback.
9. Personalized recommendations.
10. Knowledge map.
11. Persistent learning profile.
12. Career pathway.

Do not implement everything at once.

Never claim a feature or test works unless it has been verified.
## Scope Discipline

The repository holds only part of the Bousla vision. Before acting, say which kind of task it is:

- existing implementation (explain what is there),
- bug fix,
- refactoring,
- new feature,
- research or experiment,
- future planning.

Treat the code and verified tests as the truth. When `docs/` and the code disagree, point out the difference instead of silently picking one. Do not invent file paths, functions, APIs, data, AI capabilities, survey findings or results.

## Collaboration

Act as an engineering partner, not an order taker. If an idea is technically weak, unsafe, needlessly complex or works against the project's goals (for example, an "approve all" button that skips human review of AI drafts), say why and propose a better option.

Explain the reasoning behind technical decisions and their trade-offs in plain language; the team is learning while building. Briefly explain any necessary jargon. Reply in the language the team member writes in (often Arabic).

## Educathon 2026 Criteria

Competition day: Saturday 28 November 2026. Weights are in `docs/project-context.md`: educational relevance 30%, AI quality and originality 25%, feasibility and impact 20%, ethics, inclusivity and transparency 15%, presentation and prototype 10%.

For every feature, consider:

1. What educational problem does it solve?
2. How does AI add real value (not a superficial add-on)?
3. Can it be built and demonstrated before the competition?
4. What evidence shows it is useful (e.g. the AI-draft review statistics)?
5. What privacy, ethics or accessibility concerns does it raise?
6. How will judges see its value in the demo?

Prefer a working, demonstrable end-to-end flow over ambitious unfinished features (see "If time runs short" in `docs/implementation-plan.md`). Never optimize for scoring at the expense of a genuinely useful tool.

## Team Workflow

- Four people. Folder ownership is in `src/app/README.md`; tell the owner before changing their folder.
- Work on a branch, open a pull request, merge only after `flutter analyze` and `flutter test` pass on a developer machine.
- After pulling: `dart pub get` in `src/engine`, then `flutter pub get` and `flutter gen-l10n` in `src/app`. A stale generated `app_localizations.dart` shows new keys as "isn't defined for the type 'AppLocalizations'".
- UI strings go in both `app_en.arb` and `app_ar.arb`, prefixed by area (`instructor…`, `student…`, `review…`).
- In widget tests, avoid `pumpAndSettle()` while a text field is focused (the blinking cursor never settles).
- Update the status lines in `docs/implementation-plan.md` after each verified step, saying exactly what was run and where.
