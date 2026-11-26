# Bousla — Demo Script

Competition: Saturday 28 November 2026. Site: https://bousla-educathon.web.app
Status labels below (updated 25 Nov): **ready** = used on the live site · **built, check Friday** = implemented and tested (automated tests and the emulator) but not yet run on the live site or with live Gemini; the Friday rehearsal decides · say only what is true on the day.

Rule: never present an unfinished feature as working. If a step fails, use its fallback and say so plainly.

## Before the demo (Friday rehearsal + Saturday morning)

| Check | How | Who |
|---|---|---|
| Site is the latest build | `.\bousla deploy` on Friday, then open in a private window | Maysam |
| Venue network reaches the site, Firebase, `www.gstatic.com` and `www.google.com/recaptcha` | Open the site on a phone on the venue Wi-Fi; bring a phone hotspot as backup | Everyone |
| Instructor signed in on the presentation laptop | `/#/instructor`, account of the course owner | Maysam |
| 4–6 approved questions in the course, at least one concept and its prerequisite (e.g. `db_pk_*` and `db_fk_*`) | Review screen, "Approved" tab | Maysam |
| Approved resources for the concepts the questions test, at least one in Arabic, so feedback has next steps | **مصادر التعلّم** screen: add by hand (title, link, kind, language, concepts) | Maysam |
| AI resource suggestions made once and checked; keep one suggestion "waiting for a link" to show live | **مصادر التعلّم** → "Suggest resources (AI)", Thursday after 10:00 | Maysam |
| Light theme on the presentation laptop (clearer on a projector) | Sun/moon button next to the language button | Maysam |
| AI drafts already made from 2–3 real lectures and reviewed | Thursday after 10:00 (Gemini quota renews then); keep at least one group still "waiting" to review live | Maysam |
| Gemini quota not spent on Saturday (20 requests a day, shared by question drafts, resource suggestions, feedback explanations and teaching tactics) | Nobody presses an AI button on Saturday before the demo except the one feedback release | Everyone |
| Friday rehearsal session renamed so the past-sessions list reads well (e.g. "Rehearsal — keys") | Past sessions → rename | Maysam |
| Team phones charged, browser open on the site | 4 phones | Everyone |
| Offline fallback works | `.\bousla demo` on the laptop (red "LOCAL DEMO" ribbon) | Maysam |

## The demo (3–5 minutes: aim for 4, cut to 3 with the list below)

### 1. The problem (20 s)
Passing a course does not show *which* concept a student is missing, or whether the real cause is an earlier concept. Instructors see grades, not understanding.

### 2. AI drafts, the instructor decides (60 s) — ready
- Open **مراجعة الأسئلة** (review). Show the group "AI suggestions (N) — from «lecture.pdf» · model · time".
- Open one draft: Arabic and English, the page it came from, "AI draft" tag.
- **Edit** one (e.g. a weak Arabic term) and **reject** one with a reason. Point at the line "AI drafts: N · approved as is · edited · rejected" — this is how we measure AI quality, with real numbers.
- Say: there is no "approve all". Every AI draft is seen by a person before a student sees it.
- No live drafting in a 3–5 minute slot: it can take up to a minute. Show the drafts made on Wednesday.
- **Resources (20 s, built, check Friday):** open **مصادر التعلّم**. Show one AI suggestion waiting for a link: kind, where to look, search words, what it should cover, and *no link*. Say: models invent links, so the AI only describes; the instructor finds the real resource and approves it. Press **إضافة الرابط واعتماده**, paste a link you prepared, save.
- Fallback: none needed (nothing here depends on Gemini at demo time).

### 3. Students join in seconds (60 s) — ready
- **إنشاء الجلسة** → code, link and QR. Press **عرض كبير للصف** and project the QR.
- Judges and team scan it; no app to install, no account, no name asked.
- One phone in Arabic, one in English (language switch at the top). Point out: same question IDs, scoring by option, so results do not depend on the language.
- The instructor screen updates live: "طلاب أجابوا · مجموع الإجابات".
- Fallback: type the code on `/#/join` instead of scanning.

### 4. What the class understands (45 s) — browser rehearsal verified in part (Yasmeen)
- Under the counter: each concept's difficulty with its evidence (respondents, accuracy), weakest first.
- A *possible* prerequisite signal, in cautious words ("قد يكون … سبباً محتملاً"). The targeted offline tests passed, but a live signal has not yet been observed in the 26 Nov rehearsal. Show it only if present, using normal mode (the detailed signal is hidden in presentation mode). Use the rule-based teaching actions if the optional Gemini tactic is unavailable or unverified.
- Browser rehearsal: 3 participant records, 49 answers, 6 visible concepts and 4 hidden. Presentation mode worked on the computer; physical projector testing remains pending. Past-session rename was reported complete. See [QA log](qa/Bousla_QA_2026-11-26.md).
- Privacy: a concept answered by fewer than 3 students shows no numbers. With 1–2 students the panel shows only a session overview (overall % correct and which concepts to start with, no numbers per concept). With just one participant the overall result is theirs, so do not claim complete anonymity.
- Fallback: a session from the Friday rehearsal with the team as students (say it is the rehearsal session).

### 5. Each student's feedback (45 s) — built, check Friday (Lina)
- **Close the session → Release feedback.** Phones switch to personal feedback: state per concept with "X of Y correct", next steps with approved resources in the student's language, a short explanation labelled "AI-generated".
- Next steps show the resources approved in the resources screen, the student's language first: the link made in part 2 can appear here.
- **Show my knowledge map** opens the session map (foundations first), which the student can save to the phone.
- Say: the AI explains engine results; it never changes a score or a state, and if it fails, a fixed template is shown instead.
- Fallback: show the template feedback only (AI explanation turned off in the release dialog). If a phone says there is no feedback for it, open the same link again on that phone (feedback belongs to the browser that answered); this was seen once on the live site and is still being checked.

### 6. Privacy and limits, said plainly (20 s)
Say two sentences: "Students join anonymously for one session, answer keys are readable only by the instructor, and the class view shows no per-concept numbers for groups under 3. Our limits: a free AI quota, provisional thresholds, and content still under team review."

Keep for questions (do not read out):
- No longitudinal tracking is claimed without identity linking.
- Security rules are tested on the emulator (36 tests); only approved instructor accounts can create courses and sessions.
- AI resource suggestions with any link or domain name are dropped automatically; students only ever get approved resources.
- Gemini runs through Firebase with App Check; course files are not stored.
- The instructor app must stay open while scoring (no paid server).

### 7. Close (10 s)
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
| 2, 5 — AI drafts with human review and measured quality; AI resource descriptions without invented links; AI explanations with guards | AI quality and originality (25%) |
| 3 — live on real phones, no install | Feasibility and impact (20%) |
| 2, 6 — no "approve all", privacy rules, honest limits | Ethics, inclusivity, transparency (15%) |
| Whole flow in 3–5 minutes, in Arabic and English | Presentation and prototype (10%) |

## Timing

Slot: 3–5 minutes (confirmed 24 Nov). Planned total: about 4 min 40 s (part 2 now includes resources).

To get down to 3 minutes, cut in this order:
1. Part 1 → one sentence (−10 s).
2. Part 2 → show the stats line and one edit only, skip the reject (−20 s); show the resource suggestion without adding its link (−10 s).
3. Part 3 → one phone instead of two languages; mention the language switch (−20 s).
4. Part 6 → one sentence (−10 s).

Never cut parts 4 and 5 when they work at the rehearsal: they carry the 30% criterion. If part 4 or 5 is not ready, give its time to part 3 (more phones joining live).

Rehearse with a timer on Friday, on the presentation laptop and network.
