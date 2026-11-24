#!/usr/bin/env bash
# Bousla commands for macOS/Linux. Same commands as scripts/bousla.ps1
# (Windows: .\bousla). Usage: ./scripts/bousla.sh help
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/src/app"; FB="$ROOT/firebase"
ENV_FILE="$APP/firebase.env.json"; EMU_FILE="$APP/firebase.env.emulator.json"
cmd="${1:-help}"; shift || true

fail() { echo "X $*" >&2; exit 1; }
run() { local dir="$1"; shift; echo "> $*"; (cd "$dir" && "$@") || fail "$1 failed"; }

check_env() {
  local file="$1"
  [ -f "$file" ] || fail "Missing $file. Copy src/app/firebase.env.example.json and fill it from Firebase console -> Project settings -> Your apps -> Config."
  node -e '
    const fs = require("fs"); const file = process.argv[1];
    let cfg; try { cfg = JSON.parse(fs.readFileSync(file, "utf8")); }
    catch (e) { console.error(`X ${file} is not valid JSON: ${e.message}`); process.exit(1); }
    const problems = [];
    for (const n of ["FIREBASE_API_KEY","FIREBASE_APP_ID","FIREBASE_MESSAGING_SENDER_ID","FIREBASE_PROJECT_ID"]) {
      const v = String(cfg[n] ?? "");
      if (!v.trim()) problems.push(`${n} is empty`);
      else if (/[^\x21-\x7E]/.test(v)) problems.push(`${n} contains hidden characters (e.g. dots copied from a masked key). Copy it again from the Firebase console.`);
    }
    const key = String(cfg.FIREBASE_API_KEY ?? "");
    if (!cfg.USE_FIREBASE_EMULATOR && key && !/^AIza[0-9A-Za-z_-]{35}$/.test(key))
      problems.push(`FIREBASE_API_KEY does not look like a Firebase key (starts with AIza, 39 characters; this one has ${[...key].length}).`);
    if (problems.length) { console.error(`Problems in ${file}:`); for (const p of problems) console.error(`  - ${p}`); process.exit(1); }
    console.log(`OK ${file} (project ${cfg.FIREBASE_PROJECT_ID})`);
  ' "$file"
}
ensure_npm() { [ -d "$FB/node_modules" ] || run "$FB" npm install; }

case "$cmd" in
  check) check_env "$ENV_FILE" ;;
  deploy)
    check_env "$ENV_FILE"; ensure_npm
    run "$APP" flutter pub get
    run "$APP" flutter build web --no-web-resources-cdn --dart-define-from-file=firebase.env.json
    run "$FB" npx firebase deploy --only hosting,firestore:rules
    echo "Done: https://bousla-educathon.web.app  (press Ctrl+Shift+R in the browser)" ;;
  rules) ensure_npm; run "$FB" npx firebase deploy --only firestore:rules ;;
  run) check_env "$ENV_FILE"; run "$APP" flutter run -d chrome --dart-define-from-file=firebase.env.json ;;
  demo) run "$APP" flutter run -d chrome ;;
  emulators) ensure_npm; run "$FB" npx firebase emulators:start --only auth,firestore --project demo-bousla ;;
  emulator-run) check_env "$EMU_FILE"; run "$APP" flutter run -d chrome --dart-define-from-file=firebase.env.emulator.json ;;
  seed) check_env "$ENV_FILE"; ensure_npm; run "$FB" node tools/seed.mjs --approve-concepts "$@" ;;
  test)
    run "$APP" flutter pub get; run "$APP" flutter analyze; run "$APP" flutter test
    ensure_npm; run "$FB" npm test ;;
  *) cat <<'HELP'
Bousla commands (macOS/Linux: ./scripts/bousla.sh <command>, Windows: .\bousla <command>):

  deploy        check settings, build, publish site + rules
  check         only check src/app/firebase.env.json
  run           app in Chrome on the real Firebase project
  demo          offline demo mode (no Firebase, no internet)
  seed          load the course as the instructor (--force to overwrite)
  rules         publish only the security rules
  emulators     local Firebase for testing (keep open)
  emulator-run  app in Chrome on the local emulators
  test          flutter analyze + flutter test + rules tests
HELP
  ;;
esac
