# AI level 2 — real Gemini evaluation

Run: 2026-11-26T21:42:55.507559Z. Cases: 20 profiles (26 students), one request.

Route: Firebase AI Logic (project bousla-educathon), as in the app, with an App Check token from a debug token.

Requests:
- `gemini-3.8-flash`: no answer (HTTP 500): {   "error": {     "code": 500,     "message": "This model is currently experiencing high demand. Spikes in demand are usually temporary. Please try again later.",     "status": "INTERNAL"   } } 
- `gemini-3.5-flash-lite`: answered (HTTP 200)

Model that answered: `gemini-3.5-flash-lite`.

| # | Profile | Request | Result | Guard(s) / reason | Fallback used |
|---|---|---|---|---|---|
| 1 | strong everywhere | completed | accepted |  | no |
| 2 | strong, more answers | completed | accepted |  | no |
| 3 | difficulty everywhere | completed | accepted |  | no |
| 4 | difficulty in keys | completed | accepted |  | no |
| 5 | insufficient evidence | completed | accepted |  | no |
| 6 | insufficient evidence, other mix | completed | accepted |  | no |
| 7 | emerging everywhere | completed | accepted |  | no |
| 8 | emerging, more answers | completed | accepted |  | no |
| 9 | weak prerequisite: not enough evidence | completed | accepted |  | no |
| 10 | weak prerequisite: possible gap | completed | accepted |  | no |
| 11 | difficulty, prerequisite mastered | completed | accepted |  | no |
| 12 | difficulty, prerequisite emerging | completed | accepted |  | no |
| 13 | SELECT gap under JOIN | completed | accepted |  | no |
| 14 | mixed 1 | completed | accepted |  | no |
| 15 | mixed 2 | completed | accepted |  | no |
| 16 | mixed with unanswered | completed | accepted |  | no |
| 17 | mixed, four answers each | completed | accepted |  | no |
| 18 | all right but too few answers | completed | accepted |  | no |
| 19 | mixed 3 | completed | accepted |  | no |
| 20 | mixed 4 | completed | accepted |  | no |

**Real Gemini success rate: 20 of 20 (100.0%)** passed all five guards; 0 used the template explanation.

Rejections per issue: none.
