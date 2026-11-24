#!/usr/bin/env node
// Adds an account to the approved instructors list (instructors/{uid}) on
// the LOCAL EMULATORS only. It uses the emulators' admin access, which the
// real project does not have; on the real project add the entry in the
// Firebase console instead (see firebase/README.md, "Approved instructors").
//
//   .\bousla emulators                     (keep open)
//   create the account in the app (.\bousla emulator-run), then:
//   cd firebase && node tools/approve_instructor.mjs teacher@example.com
//
// Options: --host <host> (default localhost), --project <id> (default
// demo-bousla, the emulator project used by the scripts).
const args = process.argv.slice(2);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const email = args.find((a) => !a.startsWith('--') && !['--host', '--project'].includes(args[args.indexOf(a) - 1]));
const host = option('--host', 'localhost');
const project = option('--project', 'demo-bousla');

if (!email) {
  console.error('Usage: node tools/approve_instructor.mjs <email> [--host localhost]');
  process.exit(1);
}
if (!project.startsWith('demo-')) {
  // Emulator project IDs start with "demo-"; refuse anything else.
  console.error(`Emulator only: project "${project}" does not start with "demo-". ` +
    'On the real project, add the instructor in the Firebase console.');
  process.exit(1);
}

// "Bearer owner" is the emulators' admin token: it works only on emulators.
const headers = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };

let users;
try {
  const res = await fetch(
    `http://${host}:9099/identitytoolkit.googleapis.com/v1/projects/${project}/accounts:query`,
    { method: 'POST', headers, body: JSON.stringify({ returnUserInfo: true }) },
  );
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  users = (await res.json()).userInfo ?? [];
} catch (e) {
  console.error(`Cannot reach the Auth emulator on ${host}:9099 (is ".\\bousla emulators" running?)\n${e.message}`);
  process.exit(1);
}

const user = users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
if (!user) {
  console.error(`No account with ${email} on the emulator. Create it in the app first (.\\bousla emulator-run).`);
  process.exit(1);
}

const res = await fetch(
  `http://${host}:8080/v1/projects/${project}/databases/(default)/documents/instructors/${user.localId}`,
  {
    method: 'PATCH',
    headers,
    body: JSON.stringify({
      fields: {
        email: { stringValue: user.email },
        approved_at: { timestampValue: new Date().toISOString() },
      },
    }),
  },
);
if (!res.ok) {
  console.error(`Could not write to the Firestore emulator: ${res.status} ${await res.text()}`);
  process.exit(1);
}
console.log(`Approved ${user.email} (UID ${user.localId}) on the emulator. Press "Check again" in the app.`);
