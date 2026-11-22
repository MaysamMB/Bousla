# Bousla (بوصلة) — Project Context

## Identity and Competition
Bousla is an AI-powered educational innovation project developed by university students from Hebron University for Educathon 2026, themed around using AI to learn differently. The challenge is to use AI to improve education and support learning through an innovative, feasible prototype.

Evaluation criteria:
- Educational relevance and impact: 30%
- Quality and originality of AI utilization: 25%
- Feasibility and potential impact: 20%
- Ethics, inclusivity, and transparency: 15%
- Presentation clarity and prototype quality: 10%

## Problem
Students can pass courses without mastering foundational concepts. Prerequisite knowledge gaps can undermine later learning, and students may discover gaps too late. Some hesitate to ask questions, struggle to understand course relationships, or lack clarity about career skills. Instructors may find it difficult to identify class-wide misunderstanding during lectures.

## Vision
Bousla is an intelligent learning compass that helps students understand what they have evidence of mastering, identify concepts that may need further learning, understand prerequisite relationships, and choose meaningful next steps. It is more than a chatbot: its value is educational insight, concept relationships, evidence-based gap identification, and actionable guidance.

## Intended Capabilities (not necessarily implemented)
### Student
- Assess understanding through course questions.
- Distinguish demonstrated mastery, possible difficulty, and insufficient evidence.
- Visualize concept relationships and learning gaps.
- Explore prerequisite concepts that may contribute to a difficulty.
- Receive actionable explanations and learning resources.
- Explore academic skills relevant to career goals.

### Instructor
- Launch short in-class questions.
- See aggregate understanding indicators and concept-level difficulty.
- Use insights to adapt teaching.
- Avoid unnecessary exposure of individual identities.

## Knowledge and Data
Keep educational content structured and human-reviewed:
- Concepts and prerequisite relationships.
- Questions mapped to concepts.
- Learning resources mapped to concepts.
- Career skills mapped to concepts/course outcomes.
- Synthetic demo data clearly labeled as synthetic.

Review relationships and content before treating them as approved.

## AI Approach
AI must add meaningful value. A possible content-preparation workflow is: provide course materials; AI proposes concepts, relationships, questions, and resources; humans review; approved content is saved in structured data; validation runs before app use.

Possible in-app AI functionality may provide personalized explanations or learning plans grounded in approved content and student evidence. A rules-based engine is not generative AI by itself; describe its role honestly and use AI only where it contributes distinct value.

## Evidence and Confidence
Always distinguish observed evidence, rule-based estimates, AI-generated interpretations, and unknown/insufficient evidence. Never describe estimates as definitive diagnoses.

## Privacy and Ethics
Minimize personal data; enforce access control in the backend; use aggregate classroom reporting; consider small-group re-identification risk; do not assume pseudonymous data is fully anonymous; do not use identifiable student data for AI training without appropriate authorization; design supportive, transparent, and accessible experiences.

## Prototype Scope
Prioritize a coherent end-to-end demo:
1. One course with reviewed concepts and prerequisite relationships.
2. Questions mapped to concepts.
3. Student answers.
4. A testable engine estimates mastery, including insufficient evidence.
5. A concept summary or map.
6. Cautious explanation of a possible prerequisite gap.
7. At least one actionable learning resource or next step.
8. Synthetic demo data when needed, clearly labeled.

Instructor dashboard, career mapping, extensive AI content tools, and other extensions come after the core flow works.

## Survey Validation
Student and faculty surveys are intended to validate the problem and solution. Do not claim findings until real responses are collected and analyzed. Keep repository summaries aggregate and non-identifying.

## Project Truth
This document describes intended direction, not implemented functionality. The repository, source code, tests, and verified execution are the authoritative evidence. Identify features as implemented, planned, experimental, or unverified.
