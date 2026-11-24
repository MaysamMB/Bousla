#!/usr/bin/env node
// Simulated students for development: N anonymous students join a session
// and answer every question (random options, half in Arabic, half in
// English), through the same security rules as real phones.
//
// Emulator only by default, so the real project's data stays clean:
//   1. .\bousla emulators          (keep open)
//   2. create a session in the app (.\bousla emulator-run), note the code
//   3. cd firebase
//      node tools/simulate_students.mjs --code ABC234 --students 6
//
// Options: --env <file> (default ../src/app/firebase.env.emulator.json),
//          --students <n> (default 6), --real (allow a non-emulator project).
// Answers are random, so results carry no educational meaning.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, signInAnonymously } from 'firebase/auth';
import {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  serverTimestamp,
  setDoc,
} from 'firebase/firestore';

const args = process.argv.slice(2);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};
const root = new URL('../../', import.meta.url);
const envFile = option('--env', fileURLToPath(new URL('src/app/firebase.env.emulator.json', root)));
const code = (option('--code', '') || '').toUpperCase().replace(/[\s-]/g, '');
const count = Number(option('--students', '6'));
const env = JSON.parse(readFileSync(envFile, 'utf8'));

if (!code) {
  console.error('Missing --code <JOIN CODE>');
  process.exit(1);
}
if (!env.USE_FIREBASE_EMULATOR && !args.includes('--real')) {
  console.error(`${envFile} is not an emulator configuration. Simulated students are for the emulator; add --real only if you mean it.`);
  process.exit(1);
}

const config = {
  apiKey: env.FIREBASE_API_KEY,
  appId: env.FIREBASE_APP_ID,
  messagingSenderId: env.FIREBASE_MESSAGING_SENDER_ID,
  projectId: env.FIREBASE_PROJECT_ID,
  authDomain: env.FIREBASE_AUTH_DOMAIN || undefined,
};

async function oneStudent(n) {
  // A separate app instance per student = a separate anonymous user.
  const app = initializeApp(config, `student-${n}`);
  const auth = getAuth(app);
  const db = getFirestore(app);
  if (env.USE_FIREBASE_EMULATOR) {
    const host = env.FIREBASE_EMULATOR_HOST || 'localhost';
    connectAuthEmulator(auth, `http://${host}:9099`, { disableWarnings: true });
    connectFirestoreEmulator(db, host, 8080);
  }
  const uid = (await signInAnonymously(auth)).user.uid;
  const session = await getDoc(doc(db, 'sessions', code));
  if (!session.exists()) throw new Error(`No session ${code}`);
  const { course_id: courseId, questions, status } = session.data();
  if (status !== 'open') throw new Error(`Session ${code} is closed`);
  await setDoc(doc(db, 'sessions', code, 'participants', uid), { joined_at: serverTimestamp() });
  const language = n % 2 === 0 ? 'ar' : 'en';
  let answered = 0;
  for (const { question_id: qid, version } of questions) {
    const q = await getDoc(doc(db, 'courses', courseId, 'questions', `${qid}_v${version}`));
    const options = q.data().options;
    const pick = options[Math.floor(Math.random() * options.length)].id;
    await setDoc(doc(db, 'sessions', code, 'responses', `${uid}_${qid}_v${version}`), {
      participant_id: uid,
      question_id: qid,
      question_version: version,
      selected_option_id: pick,
      display_language: language,
      free_text: null,
      submitted_at: serverTimestamp(),
    });
    answered++;
  }
  await deleteApp(app);
  return `student ${n} (${language}): ${answered} answers`;
}

for (let n = 1; n <= count; n++) {
  console.log(await oneStudent(n));
}
console.log(`Done: ${count} simulated students in session ${code}.`);
process.exit(0);
