# Bousla — Ethics and Privacy

These are design principles and open considerations, not claims that the implementation already satisfies them.

- Collect the minimum personal data needed.
- Prefer session identifiers for classroom participation, but do not claim pseudonymous data is guaranteed anonymous.
- Instructor views should aggregate results and avoid exposing individual responses.
- Consider suppressing results for very small groups.
- Secure personal records with backend-enforced access control.
- Do not rely on UI hiding as authorization.
- Avoid exposing answer keys and sensitive data in public/client assets where possible.
- Explain mastery and prerequisite analyses as estimates based on evidence.
- Human-review educational and AI-generated content.
- Make participation supportive and non-punitive.
- Consider accessibility and diverse learning needs.
- Document retention, deletion, consent, and access policies before real student data is used.
- Do not use identifiable student data for AI training without appropriate authorization.

## Instructor-side implementation and evidence (26 Nov 2026)

- Per-concept numbers are suppressed below 3 respondents in the instructor UI. A prerequisite signal also requires at least 3 participants with the same possible gap and both concepts visible. No participant IDs are included in the computed class-insights output.
- With 1–2 respondents, a session-level percentage and up to three concept names may appear; with one respondent the percentage reflects that person's performance. Pseudonymous participation, aggregate display and suppression are not formal anonymity or protection against every inference.
- Mastery thresholds are provisional rule-based estimates. Prerequisite associations are potential contributing gaps, not diagnoses or proof of causation. AI teaching drafts require instructor verification; the rule-based fallback stays available if the AI response is invalid.
- The rehearsal showed 6 concepts and suppressed 4 with 3 participant records. Local targeted tests passed 10/10, including a two-shared-gap suppression case. The live Gemini tactic and physical projector have not been verified by this test run.
- The public repository contains demo question answer keys; private production assessments must not publish their keys. QA evidence must contain no real student identifiers, credentials or active access links. No comprehensive security or historical Git audit is claimed.

See [QA log](qa/Bousla_QA_2026-11-26.md) and `architecture.md` for the implementation and remaining checks.
