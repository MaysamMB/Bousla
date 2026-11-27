# Bousla app (instructor + student web)

One Flutter project for both roles. See `docs/architecture.md`.

| Route | Who | Screen |
|---|---|---|
| `/` | everyone | choose role |
| `/instructor` | instructor | create and run a session |
| `/join` | student | type a join code |
| `/join/<CODE>` | student | opened from a link or QR code |
| `/instructor/review` | instructor | review AI drafts: approve, edit, reject (one, selected or all waiting), add own questions |

The app runs on **Firebase** when built with project settings, and on
**in-memory repositories** (`lib/data/fake/`, offline demo mode) otherwise:

```bash
flutter run -d chrome                                                  # in memory
flutter run -d chrome --dart-define-from-file=firebase.env.emulator.json  # local emulators
flutter run -d chrome --dart-define-from-file=firebase.env.json           # real project
```

`firebase.env.json` is git-ignored; copy `firebase.env.example.json`. Setup,
emulators, seeding and deploy: `../../firebase/README.md`. Instructor routes
are behind email/password sign-in (`InstructorGate`); students join
anonymously.

## First-time setup (once, on the first machine)

The repository holds the Dart code but not the platform folders. Generate
them, without overwriting our files:

```bash
cd src/app
flutter create . --project-name bousla_app --platforms web,android
rm test/widget_test.dart        # Windows cmd: del test\widget_test.dart
flutter pub get                 # also generates lib/l10n/app_localizations*.dart
flutter analyze
flutter test
flutter run -d chrome
```

Commit the generated `web/`, `android/` and `.metadata`. Requires a recent
Flutter (3.38 or newer; the committed `pubspec.lock` needs Dart 3.10) for the `l10n.yaml` settings used here.

> Status (26 Nov): `flutter analyze` clean and `flutter test` 275/275 in the
> cloud environment (Flutter 3.38.10); deployed at
> https://bousla-educathon.web.app. Progress per feature is in
> `docs/implementation-plan.md`.

## Who owns what

| Folder | Owner |
|---|---|
| `lib/data/` (repository interfaces, Firestore implementations), `../../firebase/` | Backend |
| `lib/features/instructor/` | Instructor app |
| `lib/features/student_web/`, `lib/shared/` | Student portal |
| `lib/features/instructor/content_review/`, `../engine/lib/src/ai/` | AI and content |

Change someone else's folder only after telling them.

## Translations

UI strings live in `lib/l10n/app_en.arb` (template) and `lib/l10n/app_ar.arb`.
Every key must exist in both. After pulling a branch that adds keys, run
`flutter gen-l10n` (or `flutter pub get`) before `flutter analyze` / `flutter test`;
otherwise the generated `lib/l10n/app_localizations*.dart` is stale and the new
keys show up as "isn't defined for the type 'AppLocalizations'". Prefix keys with your area (`instructor…`,
`student…`, `review…`) and pull before adding keys; these two files are where
merge conflicts will happen. Course content (questions, concepts) is not in ARB
files; it comes bilingual from the data.

## Fonts

Bundled in `assets/fonts/` (SIL Open Font License, `OFL.txt`), so the app
never downloads fonts at the venue:

- `NotoSans-*` — Latin letters and punctuation, subset from Noto Sans.
- `NotoSansArabic-*` — Arabic. It has no Latin letters, so mixed text such as
  "المفتاح الأساسي (Primary Key)" uses both families.
- `NotoSansMath-Symbols` — arrows and math operators only (e.g. `A → B`),
  subset from Noto Sans Math.

Source: github.com/notofonts/notofonts.github.io (unhinted TTF). Subsets were
made with `pyftsubset` (fontTools).
