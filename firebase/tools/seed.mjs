#!/usr/bin/env node
// Loads a course from data/courses/<id>/ into Firestore, owned by the
// instructor who signs in here. Uses the normal client SDK with the
// instructor's own email/password, so the security rules apply and no admin
// key is needed.
//
//   cd firebase
//   BOUSLA_EMAIL=teacher@example.com BOUSLA_PASSWORD=... node tools/seed.mjs
//
// Options:
//   --env <file>           Firebase settings (default ../src/app/firebase.env.json)
//   --course <id>          folder in data/courses (default database-systems)
//   --approve-concepts     mark concepts approved (there is no concept review
//                          screen yet; questions can only use approved concepts)
//   --approve-resources    mark resources approved
//   --force                overwrite a course that already has questions
//                          (resets review decisions made in the app!)
//
// Questions keep the status in the data files (pending_review), so the
// instructor reviews them in the app at /instructor/review.
import { readFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

import { initializeApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  signInWithEmailAndPassword,
} from 'firebase/auth';
import {
  collection,
  connectFirestoreEmulator,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  limit,
  query,
  setDoc,
  writeBatch,
} from 'firebase/firestore';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const option = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};

const root = new URL('../../', import.meta.url);
// fileURLToPath, not URL.pathname: on Windows pathname gives "/C:/...".
const envFile = option('--env', fileURLToPath(new URL('src/app/firebase.env.json', root)));
const folder = option('--course', 'database-systems');
const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const data = (file) => readJson(new URL(`data/courses/${folder}/${file}`, root));

const env = readJson(envFile);
if (!env.FIREBASE_PROJECT_ID) {
  console.error(`No FIREBASE_PROJECT_ID in ${envFile}`);
  process.exit(1);
}
if (!env.USE_FIREBASE_EMULATOR && !/^AIza[0-9A-Za-z_-]{35}$/.test(env.FIREBASE_API_KEY ?? '')) {
  console.error(`FIREBASE_API_KEY in ${envFile} is not a valid Firebase key (hidden "•" characters?). ` +
    'Copy it again from Firebase console -> Project settings -> Your apps -> Config.');
  process.exit(1);
}

const app = initializeApp({
  apiKey: env.FIREBASE_API_KEY,
  appId: env.FIREBASE_APP_ID,
  messagingSenderId: env.FIREBASE_MESSAGING_SENDER_ID,
  projectId: env.FIREBASE_PROJECT_ID,
  authDomain: env.FIREBASE_AUTH_DOMAIN || undefined,
});
const auth = getAuth(app);
const db = getFirestore(app);
if (env.USE_FIREBASE_EMULATOR) {
  const host = env.FIREBASE_EMULATOR_HOST || 'localhost';
  connectAuthEmulator(auth, `http://${host}:9099`, { disableWarnings: true });
  connectFirestoreEmulator(db, host, 8080);
}

const rl = createInterface({ input: process.stdin, output: process.stdout });
const email = process.env.BOUSLA_EMAIL || (await rl.question('Instructor email: '));
const password = process.env.BOUSLA_PASSWORD || (await rl.question('Password: '));
rl.close();

let user;
try {
  user = (await signInWithEmailAndPassword(auth, email, password)).user;
} catch (e) {
  if (!flag('--create-account')) {
    console.error(`Sign-in failed (${e.code}). Create the account in the app, or add --create-account.`);
    process.exit(1);
  }
  user = (await createUserWithEmailAndPassword(auth, email, password)).user;
}
console.log(`Signed in as ${email} on ${env.FIREBASE_PROJECT_ID}${env.USE_FIREBASE_EMULATOR ? ' (emulator)' : ''}`);

const course = data('course.json');
const concepts = data('concepts.json');
const questions = data('questions.json');
const answerKeys = data('answer_keys.json');
const resources = data('resources.json');

const courseRef = doc(db, 'courses', course.id);
const existing = await getDoc(courseRef);
if (existing.exists()) {
  if (existing.data().owner_id !== user.uid) {
    console.error(`Course ${course.id} belongs to another instructor.`);
    process.exit(1);
  }
  const hasQuestions = !(await getDocs(query(collection(courseRef, 'questions'), limit(1)))).empty;
  if (hasQuestions && !flag('--force')) {
    console.error(`Course ${course.id} already has questions. Use --force to overwrite (resets review decisions).`);
    process.exit(1);
  }
}

const list = (json, key) => (Array.isArray(json) ? json : json[key]);
const approve = (item, yes) =>
  yes ? { ...item, provenance: { ...item.provenance, status: 'approved', reviewed_by: user.uid } } : item;

await setDoc(courseRef, {
  name: course.name,
  owner_id: user.uid,
  languages: course.languages,
  default_language: course.default_language ?? 'ar',
});

const writes = [];
for (const c of list(concepts, 'concepts')) {
  writes.push([doc(courseRef, 'concepts', c.id), approve(c, flag('--approve-concepts'))]);
}
for (const q of list(questions, 'questions')) {
  writes.push([doc(courseRef, 'questions', `${q.id}_v${q.version}`), q]);
}
for (const [questionId, key] of Object.entries(answerKeys)) {
  const version = key.version ?? 1;
  writes.push([doc(courseRef, 'answer_keys', `${questionId}_v${version}`), {
    question_id: questionId,
    question_version: version,
    correct_option_id: key.correct_option_id,
  }]);
}
for (const r of list(resources, 'resources')) {
  writes.push([doc(courseRef, 'resources', r.id), approve(r, flag('--approve-resources'))]);
}

for (let i = 0; i < writes.length; i += 400) {
  const batch = writeBatch(db);
  for (const [ref, value] of writes.slice(i, i + 400)) batch.set(ref, value);
  await batch.commit();
}
console.log(`Loaded ${course.id}: ${list(concepts, 'concepts').length} concepts, ` +
  `${list(questions, 'questions').length} questions, ${Object.keys(answerKeys).length} answer keys, ` +
  `${list(resources, 'resources').length} resources.`);
process.exit(0);
