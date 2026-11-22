# Bousla (بوصلة) — Project Context

## Identity and Competition

Bousla is an AI-powered educational innovation project developed by university students from Hebron University for Educathon 2026, themed around using AI to learn differently.

Evaluation criteria:
- Educational relevance and impact: 30%
- Quality and originality of AI utilization: 25%
- Feasibility and potential impact: 20%
- Ethics, inclusivity, and transparency: 15%
- Presentation clarity and prototype quality: 10%

## Problem

Students can pass courses without mastering foundational concepts. Prerequisite knowledge gaps can undermine later learning, and students may discover gaps too late. Some hesitate to ask questions, struggle to understand course relationships, or lack clarity about career skills. Instructors may find it difficult to identify class-wide misunderstanding during lectures.

## Product Vision

Bousla is an AI-powered educational intelligence platform designed to help students understand their actual learning progress and help instructors identify knowledge gaps within their classrooms.

Bousla uses an instructor-centered application and a responsive student web portal.

Students do not need to install a separate application. They join through a shared link or QR code.

## Main Product Components

### 1. Instructor Application
- Manage courses and learning sessions.
- Create and launch assessments.
- Share session links and QR codes.
- Monitor classroom participation.
- View real-time aggregate learning insights.
- Identify difficult concepts and possible prerequisite gaps.
- Review student learning progress according to privacy permissions.

### 2. Student Web Portal
- Join sessions using a link or QR code.
- Answer questions using mobile or desktop browsers.
- Support Arabic and English.
- View personal assessment feedback.
- Access a personal knowledge map.
- Receive personalized learning recommendations.
- Explore career pathways and skill gaps.

### 3. Shared Educational Intelligence Engine

The engine is the core of Bousla. Its responsibilities include:
- Mapping questions to educational concepts.
- Estimating student mastery.
- Identifying possible prerequisite knowledge gaps (possible root causes, never definitive diagnoses).
- Analyzing classroom learning patterns.
- Recommending learning resources.
- Building personalized learning paths.
- Mapping academic concepts to career skills.

## Arabic and English Support

Arabic and English are first-class supported languages.

- Arabic interfaces must support RTL.
- English interfaces must support LTR.
- Questions and answer choices should have Arabic and English versions.
- Students can select their preferred language.
- Concept IDs and question IDs must remain language-independent.
- Original free-text responses must be preserved.
- AI evaluation of free-text answers must support both languages.
- Never rely on simple exact string matching for multilingual answers.
- AI evaluations must use a consistent rubric and abstain when uncertain.
- Learning recommendations should use the student's preferred language whenever possible.

For the MVP, prioritize bilingual multiple-choice questions and structured scoring before advanced free-text AI evaluation.

## Student Learning Profile

Each student may have a personal learning profile containing:
- Assessment history.
- Concept mastery estimates.
- Knowledge map.
- Possible learning gaps.
- Recommended resources.
- Learning progress.
- Career skill development.

A session-only anonymous participant must not be treated as a persistent student identity.

Persistent profiles require a secure and privacy-conscious identity or return mechanism (see `docs/architecture.md`, Identity).

## AI Strategy

AI can assist in:
- Extracting concepts from course materials.
- Suggesting prerequisite relationships.
- Generating bilingual questions.
- Mapping career skills.
- Producing personalized explanations.
- Recommending learning activities.

Generated educational content must be validated and human-reviewed.

The deterministic educational engine handles scoring and evidence aggregation. AI must not invent student performance or present uncertain conclusions as facts. A rules-based engine is not generative AI by itself; describe each component's role honestly.

## Evidence and Confidence

Always distinguish observed evidence, rule-based estimates, AI-generated interpretations, and unknown/insufficient evidence. Never describe estimates as definitive diagnoses.

## Privacy

- Instructor dashboards should show aggregated results by default.
- Personal student profiles must be protected.
- Backend authorization is mandatory.
- Pseudonymous identifiers are not guaranteed anonymity.
- Personal links and access tokens must be protected.
- Do not expose answer keys or API secrets in public client code.
- Use synthetic demo data when real student data is unavailable.

## MVP Priorities

1. Instructor creates a session.
2. Bousla generates a join link and QR code.
3. Students answer through a responsive web portal.
4. Questions are mapped to approved concepts.
5. The engine estimates mastery.
6. Instructor sees aggregate classroom insights.
7. Students receive personal feedback when enabled.
8. The system identifies possible prerequisite gaps.
9. Students receive actionable learning recommendations.
10. Arabic and English journeys both work.

Knowledge maps, persistent learning profiles, advanced AI assessment, and career pathways should be developed in stages.

## Survey Validation

Student and faculty surveys are intended to validate the problem and solution. Do not claim findings until real responses are collected and analyzed. Keep repository summaries aggregate and non-identifying. Do not commit raw respondent data.

## Project Truth

This document describes the product vision, not proof of implementation. Actual source code and verified tests determine implementation status. Identify features as implemented, planned, experimental, or unverified.
