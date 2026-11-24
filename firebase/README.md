# Firebase backend (owner: backend)

What is here:

| File | What it does |
|---|---|
| `firestore.rules` | Security rules: the real access control (docs/architecture.md §6). |
| `test/rules.test.mjs` | 27 rules tests, run on the Firestore emulator. |
| `tools/seed.mjs` | Loads a course from `data/courses/` into Firestore as the signed-in instructor. |
| `../firebase.json` | Firestore, Hosting (`src/app/build/web`) and emulator settings. |

The app's Firebase code is in `src/app/lib/data/firebase/`. Without Firebase
settings the app still runs on the in-memory repositories: that is the
**offline demo mode**.

## Requirements

Node 20+ and Java 11+ (for the emulators). Then once:

```bash
cd firebase
npm install
```

## Run the rules tests

```bash
cd firebase
npm test
```

## Try everything locally (no Firebase project needed)

Terminal 1, the emulators (Auth + Firestore, with the real rules):

```bash
cd firebase
npx firebase emulators:start --only auth,firestore --project demo-bousla
```

Terminal 2, load the course (creates the instructor account in the emulator):

```bash
cd firebase
BOUSLA_EMAIL=teacher@test.dev BOUSLA_PASSWORD=secret123 node tools/seed.mjs --env ../src/app/firebase.env.emulator.json --approve-concepts --create-account
```

Terminal 3, the app:

```bash
cd src/app
flutter run -d chrome --dart-define-from-file=firebase.env.emulator.json
```

Sign in as `teacher@test.dev` / `secret123`, approve questions in the review
screen, create a session, and join from another browser profile (or a
private window) with the code. Each browser is a different anonymous student.

To test from phones on the same Wi-Fi: set `FIREBASE_EMULATOR_HOST` in a copy
of `firebase.env.emulator.json` to your computer's LAN IP, then serve the
built app on that IP:

```bash
flutter build web --no-web-resources-cdn --dart-define-from-file=firebase.env.lan.json
cd build/web && python3 -m http.server 5000 --bind 0.0.0.0
```

## Set up the real project (once)

1. [console.firebase.google.com](https://console.firebase.google.com) → Add project (Spark, no-cost plan).
2. **Build → Authentication → Sign-in method**: enable **Email/Password** and **Anonymous**.
3. **Build → Firestore Database → Create database** (production mode; the rules below replace the defaults).
4. **Project settings → Your apps → Add app → Web**. Copy the config values into
   `src/app/firebase.env.json` (copy of `firebase.env.example.json`, git-ignored).
   These values identify the project; they are not secrets.
5. Deploy the rules, then the app:

   ```bash
   cd firebase
   npx firebase login
   # .firebaserc already points to bousla-educathon
   npx firebase deploy --only firestore:rules
   cd ../src/app
   flutter build web --no-web-resources-cdn --dart-define-from-file=firebase.env.json
   cd ../../firebase
   npx firebase deploy --only hosting
   ```

   The app is then at `https://<project-id>.web.app`. Join links look like
   `https://<project-id>.web.app/#/join/ABC234`.

6. Create the instructor account in the app (`/instructor` → Create account),
   then load the course with the same email:

   ```bash
   cd firebase
   node tools/seed.mjs --approve-concepts
   ```

   It asks for the email and password. Questions arrive as `pending_review`;
   approve them in the review screen. Running it again refuses to overwrite
   review decisions unless you add `--force`.

## Data layout

```
courses/{courseId}                         name, owner_id
courses/{courseId}/concepts/{conceptId}
courses/{courseId}/questions/{id}_v{n}     one document per version
courses/{courseId}/answer_keys/{id}_v{n}   owner only
courses/{courseId}/resources/{resourceId}
sessions/{CODE}                            document ID = join code
sessions/{CODE}/participants/{uid}
sessions/{CODE}/responses/{uid}_{id}_v{n}  written once, while open
sessions/{CODE}/aggregates/summary         owner only (later)
sessions/{CODE}/feedback/{uid}             that student, after release (later)
```

## Venue network

The Flutter web app needs `www.gstatic.com` (Firebase JS libraries) and
Firebase's own hosts. `--no-web-resources-cdn` makes the Flutter engine
(CanvasKit) load from our own hosting, but the Firebase libraries still come
from gstatic. Without internet Firestore cannot work anyway, so:

- test the venue network before the demo, and bring a phone hotspot;
- the fallback is the **offline demo mode**: build without
  `--dart-define-from-file` (in-memory data, everything in one browser).

## Known limits

- Students can read any *approved* question or concept if they know its ID
  (questions contain no answers). The architecture's stricter "only for
  courses of a session you joined" is not enforced yet.
- No App Check yet (planned with Firebase AI Logic).
- The instructor app must stay open during a session (scoring runs there,
  Option A).
- Android was not built with Firebase; the target for the demo is the web app.
