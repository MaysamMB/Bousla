# Bousla commands for Windows (PowerShell). From the repository root:
#
#   .\bousla help
#
# (bousla.cmd runs this file, so no PowerShell execution-policy change is
# needed.) The same commands for macOS/Linux: ./scripts/bousla.sh
param(
  [Parameter(Position = 0)] [string] $Command = 'help',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Rest = @()
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root 'src/app'
$Fb = Join-Path $Root 'firebase'
$EnvFile = Join-Path $App 'firebase.env.json'
$EmuFile = Join-Path $App 'firebase.env.emulator.json'

function Fail($message) {
  Write-Host "X $message" -ForegroundColor Red
  exit 1
}

# Runs a program and stops if it fails.
function Run([string] $dir, [string] $exe, [string[]] $arguments) {
  Write-Host "> $exe $($arguments -join ' ')" -ForegroundColor Cyan
  Push-Location $dir
  try {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { Fail "$exe failed (exit code $LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

# Checks firebase.env.json before anything is built with it.
function Check-Env([string] $file) {
  if (-not (Test-Path $file)) {
    Fail "Missing $file. Copy src/app/firebase.env.example.json and fill it from Firebase console -> Project settings -> Your apps -> Config."
  }
  try {
    $cfg = Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Fail "$file is not valid JSON: $($_.Exception.Message)"
  }
  $problems = @()
  foreach ($name in 'FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_MESSAGING_SENDER_ID', 'FIREBASE_PROJECT_ID') {
    $value = [string] $cfg.$name
    if ([string]::IsNullOrWhiteSpace($value)) { $problems += "$name is empty" }
    elseif ($value -match '[^\x21-\x7E]') { $problems += "$name contains hidden characters (e.g. dots copied from a masked key). Copy it again from the Firebase console." }
  }
  $key = [string] $cfg.FIREBASE_API_KEY
  if (-not $cfg.USE_FIREBASE_EMULATOR -and $key -and $key -notmatch '^AIza[0-9A-Za-z_-]{35}$') {
    $problems += "FIREBASE_API_KEY does not look like a Firebase key (starts with AIza, 39 characters; this one has $($key.Length))."
  }
  if ($problems.Count -gt 0) {
    Write-Host "Problems in ${file}:" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
  }
  Write-Host "OK $file (project $($cfg.FIREBASE_PROJECT_ID))" -ForegroundColor Green
  if (-not $cfg.USE_FIREBASE_EMULATOR -and [string]::IsNullOrWhiteSpace([string] $cfg.FIREBASE_APPCHECK_SITE_KEY)) {
    Write-Host "Note: FIREBASE_APPCHECK_SITE_KEY is empty, so App Check is off (see firebase/README.md)." -ForegroundColor Yellow
  }
}

function Ensure-Npm {
  if (-not (Test-Path (Join-Path $Fb 'node_modules'))) { Run $Fb 'npm' @('install') }
}

switch ($Command) {
  'check' {
    Check-Env $EnvFile
  }
  'deploy' {
    # Build the web app with the real project and publish it + the rules.
    Check-Env $EnvFile
    Ensure-Npm
    Run $App 'flutter' @('pub', 'get')
    Run $App 'flutter' @('build', 'web', '--no-web-resources-cdn', '--dart-define-from-file=firebase.env.json')
    Write-Host 'Reminder: the rules require approved instructors (Firestore -> instructors/{UID}). See firebase/README.md.' -ForegroundColor Yellow
    Run $Fb 'npx' @('firebase', 'deploy', '--only', 'hosting,firestore:rules')
    Write-Host 'Done: https://bousla-educathon.web.app  (press Ctrl+Shift+R in the browser)' -ForegroundColor Green
  }
  'rules' {
    Write-Host 'Reminder: the rules require approved instructors (Firestore -> instructors/{UID}). See firebase/README.md.' -ForegroundColor Yellow
    Ensure-Npm
    Run $Fb 'npx' @('firebase', 'deploy', '--only', 'firestore:rules')
  }
  'run' {
    # The app in Chrome on the real Firebase project.
    Check-Env $EnvFile
    Run $App 'flutter' @('run', '-d', 'chrome', '--dart-define-from-file=firebase.env.json')
  }
  'demo' {
    # Offline demo mode: in-memory data, no Firebase, no internet needed.
    Run $App 'flutter' @('run', '-d', 'chrome')
  }
  'emulators' {
    # Local Firebase (Auth + Firestore with the real rules). Keep it open,
    # then use "emulator-run" in another terminal.
    Ensure-Npm
    Run $Fb 'npx' @('firebase', 'emulators:start', '--only', 'auth,firestore', '--project', 'demo-bousla')
  }
  'emulator-run' {
    Check-Env $EmuFile
    Run $App 'flutter' @('run', '-d', 'chrome', '--dart-define-from-file=firebase.env.emulator.json')
  }
  'seed' {
    # Load the Database Systems course as the instructor (asks for email and
    # password). Extra options are passed on, e.g.: .\bousla seed --force
    Check-Env $EnvFile
    Ensure-Npm
    Run $Fb 'node' (@('tools/seed.mjs', '--approve-concepts') + $Rest)
  }
  'approve' {
    # Approve an instructor account on the local emulators: .\bousla approve EMAIL
    if ($Rest.Count -lt 1) { Fail 'Usage: .\bousla approve <EMAIL>  (emulators only; real project: Firebase console)' }
    Run $Fb 'node' (@('tools/approve_instructor.mjs') + $Rest)
  }
  'simulate' {
    # Simulated students on the local emulators: .\bousla simulate ABC234
    if ($Rest.Count -lt 1) { Fail 'Usage: .\bousla simulate <JOIN CODE> [--students 6]' }
    Ensure-Npm
    Run $Fb 'node' (@('tools/simulate_students.mjs', '--code') + $Rest)
  }
  'test' {
    Run $App 'flutter' @('pub', 'get')
    Run $App 'flutter' @('analyze')
    Run $App 'flutter' @('test')
    Ensure-Npm
    Run $Fb 'npm' @('test')
  }
  default {
    Write-Host @'
Bousla commands (run from the repository root):

  .\bousla deploy        check settings, build, publish site + rules
  .\bousla check         only check src/app/firebase.env.json
  .\bousla run           app in Chrome on the real Firebase project
  .\bousla demo          offline demo mode (no Firebase, no internet)
  .\bousla seed          load the course as the instructor (--force to overwrite)
  .\bousla rules         publish only the security rules
  .\bousla emulators     local Firebase for testing (keep open)
  .\bousla emulator-run  app in Chrome on the local emulators
  .\bousla approve EMAIL approve an instructor account (emulators only)
  .\bousla simulate CODE simulated students answer session CODE (emulators only)
  .\bousla test          flutter analyze + flutter test + rules tests
'@
  }
}
