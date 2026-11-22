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