# Bousla — Implementation Plan for Claude Code

This is a proposed plan, not a claim that features or architecture are implemented. Inspect the repository first and adapt.

## Phase 0 — Repository reconnaissance
- Inspect tree, README, manifests, Flutter app, Firebase configuration, existing data, and tests.
- Identify implemented, broken, incomplete, and proposed features.
- Report architecture, runnable commands, and blockers.
- Do not rewrite or scaffold everything.
Deliverable: repository audit and adjusted plan.

## Phase 1 — Course data
- Focus on one course (Database Systems is a possible choice, but verify with the team).
- Define a documented JSON schema for concepts, prerequisite links, questions, and resources.
- Build a small human-reviewed dataset.
- Map questions to concepts and appropriate skills/difficulty.
- Add source/provenance fields where practical; label demo data synthetic.
- Validate references, duplicate IDs, missing fields, JSON validity, and cycles if the graph must be acyclic.
Deliverable: small dataset, validator, and tests.

## Phase 2 — Pure Dart engine
Keep it independent of Flutter UI, Firebase, and network calls.
Implement incrementally:
1. Required models.
2. Provisional mastery estimation and insufficient evidence.
3. Concept-level summary.
4. Prerequisite evidence analysis: suggest possible contributing gaps only when supported; otherwise suggest more assessment.
5. Learning resource/next-step selection.

Starter heuristics are provisional, configurable, and not scientifically validated:
- Insufficient evidence: fewer than 2 responses.
- Potential difficulty: at least 2 responses and accuracy below 50%.
- Demonstrated mastery: at least 3 responses and accuracy >=75%.
- Define precedence carefully and test boundaries. Other results should be treated as uncertain/emerging rather than forcing a conclusion.
Deliverable: tests for boundaries, empty input, unknown references, and prerequisite analysis.

## Phase 3 — Student end-to-end flow
- Load approved course content.
- Present questions and collect responses.
- Run the engine.
- Display evidence, uncertainty, and next steps.
- Avoid exposing answer keys in client assets if security matters.
- Use synthetic demo data if needed.
Deliverable: a reliable student flow.

## Phase 4 — Knowledge map and recommendations
- Visualize concepts and relationships.
- Show status and insufficient evidence distinctly.
- Let learners explore prerequisite links.
- Provide reviewed resources.
- Avoid claiming prerequisites are proven causes.
Deliverable: usable map and next step.

## Phase 5 — Backend and privacy (only as needed)
- Define minimal collections and access patterns.
- Establish authentication or a bounded anonymous-session approach.
- Enforce access control through backend rules.
- Separate personal learning data from classroom aggregates.
- Prevent instructor access to identifiable responses unless explicitly justified.
- Consider small-group thresholds and test rules.
Deliverable: tested rules and documented data flow.

## Phase 6 — Instructor insights
- Launch short questions.
- Collect responses with appropriate identifiers.
- Display aggregate results only.
- Test lifecycle, duplicate/late responses, empty states, and small groups.
Deliverable: privacy-conscious classroom demo.

## Phase 7 — AI and optional Python tools
Only after the core data and app flow are stable:
- Add Python tools where useful.
- AI proposes content based on provided materials.
- Validate structured outputs.
- Human-review before approving content.
- Protect credentials, ground in approved content, and handle failure gracefully if in-app LLM calls are used.
Deliverable: bounded, demonstrable, honest AI functionality.

## Phase 8 — Career pathway (optional)
- Define a small skill-to-concept map for one target role.
- Identify gaps only with adequate evidence.
- Offer an achievable path.
- Do not claim job-posting analysis is reliable or implemented without verification.
Deliverable: small career-path demo if time permits.

## Phase 9 — Demo hardening
- Freeze scope.
- Run tests and analysis.
- Test the complete flow on presentation device/network.
- Prepare synthetic fallback data.
- Check privacy, accessibility, and error/empty/loading states.
- Prepare timed demo and backup.
- Document limitations.

## Priority when time is limited
1. Data integrity and one course.
2. Engine and tests.
3. Student question-to-insight flow.
4. Prerequisite explanation and resource.
5. Knowledge map.
6. Instructor aggregate demo.
7. Career pathway.
8. Extra automation and polish.

## Execution discipline
Work in small slices; do not implement all phases in one giant change. After Phase 0, present the audit and adjusted first slice. Proceed autonomously only when the user has explicitly asked for autonomous implementation. Never invent tests, survey findings, sources, or feature status.
