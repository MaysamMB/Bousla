# Bousla app (instructor + student web)

One Flutter project for both roles. See `docs/architecture.md`.

| Route | Who | Screen |
|---|---|---|
| `/` | everyone | choose role |
| `/instructor` | instructor | create and run a session |
| `/join` | student | type a join code |
| `/join/<CODE>` | student | opened from a link or QR code |

The app currently runs on **in-memory repositories** (`lib/data/fake/`), so
everyone can build screens before Firebase is connected. Swap them for the
Firestore implementations in `lib/main.dart` only.

## First-time setup (once, on the first machine)

The repository holds the Dart code but not the platform folders. Generate
them, without overwriting our files:

```bash
cd src/app
flutter create . --project-name bousla_app --platforms web,android
rm test/widget_test.dart        # default counter test from flutter create
flutter pub get                 # also generates lib/l10n/app_localizations*.dart
flutter analyze
flutter test
flutter run -d chrome
```

Commit the generated `web/`, `android/` and `.metadata`. Requires a recent
Flutter (3.32 or newer) for the `l10n.yaml` settings used here.

> Status: the files in `lib/data/` and `test/data/` were analyzed and tested
> with plain Dart. The screens, localization setup and `test/widget_smoke_test.dart`
> were written without a Flutter SDK available and have **not been compiled
> yet**. The first `flutter analyze` / `flutter test` run is their first check.

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
Every key must exist in both. Prefix keys with your area (`instructor…`,
`student…`, `review…`) and pull before adding keys; these two files are where
merge conflicts will happen. Course content (questions, concepts) is not in ARB
files; it comes bilingual from the data.

## Arabic font

Add a TTF with Arabic support (for example Noto Sans Arabic, SIL Open Font
License) to `assets/fonts/`, then uncomment the `fonts:` block in
`pubspec.yaml` and `fontFamily` in `lib/app.dart`. Bundling avoids downloading
fonts at the venue.
