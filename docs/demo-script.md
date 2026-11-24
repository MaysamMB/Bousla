# Bousla — Demo Script

Competition: Saturday 28 November 2026. Site: https://bousla-educathon.web.app
Status labels below: **ready** = works on the live site today (24 Nov) · **if ready** = depends on a task still in progress (see the team plan doc) · say only what is true on the day.

Rule: never present an unfinished feature as working. If a step fails, use its fallback and say so plainly.

## Before the demo (Friday rehearsal + Saturday morning)

| Check | How | Who |
|---|---|---|
| Site is the latest build | `.\bousla deploy` on Friday, then open in a private window | Maysam |
| Venue network reaches the site, Firebase, `www.gstatic.com` and `www.google.com/recaptcha` | Open the site on a phone on the venue Wi-Fi; bring a phone hotspot as backup | Everyone |
| Instructor signed in on the presentation laptop | `/#/instructor`, account of the course owner | Maysam |
| 4–6 approved questions in the course, at least one concept and its prerequisite (e.g. `db_pk_*` and `db_fk_*`) | Review screen, "Approved" tab | Maysam |
| AI drafts already made from 2–3 real lectures and reviewed | Done Wednesday after 10:00 (Gemini quota renews then); keep at least one group still "waiting" to review live | Maysam |
| Gemini quota not spent on Saturday | Nobody presses "Draft questions from material" before the demo | Everyone |
| Team phones charged, browser open on the site | 4 phones | Everyone |
| Offline fallback works | `.\bousla demo` on the laptop (red "LOCAL DEMO" ribbon) | Maysam |

## The demo (about 7 minutes; adjust to the slot we are given)

### 1. The problem (30 s)
Passing a course does not show *which* concept a student is missing, or whether the real cause is an earlier concept. Instructors see grades, not understanding.

### 2. AI drafts, the instructor decides (1.5 min) — ready
- Open **مراجعة الأسئلة** (review). Show the group "AI suggestions (N) — from «lecture.pdf» · model · time".
- Open one draft: Arabic and English, the page it came from, "AI draft" tag.
- **Edit** one (e.g. a weak Arabic term) and **reject** one with a reason. Point at the line "AI drafts: N · approved as is · edited · rejected" — this is how we measure AI quality, with real numbers.
- Say: there is no "approve all". Every AI draft is seen by a person before a student sees it.
- Optional, only if the network is good: press **اقتراح أسئلة من مادة**, one small file, 3 questions. One request only.
- Fallback: the drafts made on Wednesday are already in the list.

### 3. Students join in seconds (1.5 min) — ready
- **إنشاء الجلسة** → code, link and QR. Press **عرض كبير للصف** and project the QR.
- Judges and team scan it; no app to install, no account, no name asked.
- One phone in Arabic, one in English (language switch at the top). Point out: same question IDs, scoring by option, so results do not depend on the language.
- The instructor screen updates live: "طلاب أجابوا · مجموع الإجابات".
- Fallback: type the code on `/#/join` instead of scanning.

### 4. What the class understands (1.5 min) — if ready (Yasmeen's task)
- Under the counter: each concept's difficulty with its evidence (respondents, accuracy), weakest first.
- A *possible* prerequisite signal, in cautious words ("قد يكون … سبباً محتملاً").
- Privacy: a concept answered by fewer than 5 students is hidden. If the room gives fewer than 5 answers, say so: that is the protection working.
- Fallback: a session from the Friday rehearsal with the team as students (say it is the rehearsal session).

### 5. Each student's feedback (1 min) — if ready (Lina's task)
- **Close the session → Release feedback.** Phones switch to personal feedback: state per concept with "X of Y correct", next steps with approved resources in the student's language, a short explanation labelled "AI-generated".
- Say: the AI explains engine results; it never changes a score or a state, and if it fails, a fixed template is shown instead.
- Fallback: show the template feedback only (AI explanation turned off in the release dialog).

### 6. Privacy and limits, said plainly (45 s)
- Students join anonymously for one session only; no longitudinal tracking is claimed.
- Answer keys are only readable by the course owner (security rules, tested on the emulator).
- The instructor sees aggregates; small groups are hidden.
- Gemini runs through Firebase with App Check; course files are not stored.
- Limits: free Gemini quota (a few requests per day); the instructor app must stay open while scoring (no paid server); the course content is a draft reviewed by the team; mastery thresholds are provisional, not validated.

### 7. Close (15 s)
Bousla turns a short in-class quiz into what each student should learn next, and what the instructor should revisit, in Arabic and English.

## If something breaks

| Problem | What to do |
|---|---|
| No internet / Firebase unreachable | Hotspot; if still down, `.\bousla demo` (offline, in-memory, red "LOCAL DEMO" ribbon) and say it is the offline mode |
| Gemini busy or quota used up | Use the drafts made on Wednesday; the dialog's message says why |
| A phone shows an old version | Private window, or another phone |
| A student's answer seems stuck | The screen says "connection is slow"; press again, earlier answers are kept |

## Which criterion each part serves

| Part | Criterion (weight) |
|---|---|
| 4, 5 — what the class / each student understands, with evidence | Educational relevance (30%) |
| 2, 5 — AI drafts with human review and measured quality; AI explanations with guards | AI quality and originality (25%) |
| 3 — live on real phones, no install | Feasibility and impact (20%) |
| 2, 6 — no "approve all", privacy rules, honest limits | Ethics, inclusivity, transparency (15%) |
| Whole flow in 7 minutes, in Arabic and English | Presentation and prototype (10%) |

Open question: how long is our slot? Cut part 2's live drafting first, then part 6's details.
