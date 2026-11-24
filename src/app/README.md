# Bousla app (instructor + student web)

One Flutter project for both roles. See `docs/architecture.md`.

| Route | Who | Screen |
|---|---|---|
| `/` | everyone | choose role |
| `/instructor` | instructor | create and run a session |
| `/join` | student | type a join code |
| `/join/<CODE>` | student | opened from a link or QR code |
| `/instructor/review` | instructor | review AI drafts: approve, edit, reject (one, selected or all waiting), add own questions |

The app currently runs on **in-memory repositories** (`lib/data/fake/`), so
everyone can build screens before Firebase is connected. Swap them for the
Firestore implementations in `lib/main.dart` only.

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
