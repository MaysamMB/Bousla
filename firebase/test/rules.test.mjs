// Firestore security rules tests. Run on the emulator:
//   cd firebase && npm install && npm test
// See docs/architecture.md §6 for the permission table these check.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  limit,
  deleteDoc,
  writeBatch,
} from 'firebase/firestore';

const COURSE = 'database_systems';
const CODE = 'ABC234';

let env;

// Contexts. Instructors sign in with a password; students anonymously.
const instructor = () =>
  env.authenticatedContext('teacher', { firebase: { sign_in_provider: 'password' } }).firestore();
const otherInstructor = () =>
  env.authenticatedContext('teacher2', { firebase: { sign_in_provider: 'password' } }).firestore();
const student = (uid = 'student1') =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: 'anonymous' } }).firestore();
const nobody = () => env.unauthenticatedContext().firestore();
// Signed in with a password but not in the instructors list.
const unapproved = () =>
  env.authenticatedContext('stranger', { firebase: { sign_in_provider: 'password' } }).firestore();

const question = (id, status) => ({
  id,
  version: 1,
  concept_ids: ['primary_key'],
  prompt: { ar: 'سؤال', en: 'Question' },
  options: [
    { id: 'a', text: { ar: 'أ', en: 'A' } },
    { id: 'b', text: { ar: 'ب', en: 'B' } },
  ],
  provenance: { source: 'team', status },
});

const response = (uid, overrides = {}) => ({
  participant_id: uid,
  question_id: 'q_ok',
  question_version: 1,
  selected_option_id: 'a',
  display_language: 'ar',
  free_text: null,
  submitted_at: serverTimestamp(),
  ...overrides,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-bousla',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'instructors', 'teacher'), { email: 'teacher@example.com' });
    await setDoc(doc(db, 'instructors', 'teacher2'), { email: 'teacher2@example.com' });
    await setDoc(doc(db, 'courses', COURSE), {
      name: { ar: 'أنظمة قواعد البيانات', en: 'Database Systems' },
      owner_id: 'teacher',
    });
    await setDoc(doc(db, 'courses', COURSE, 'questions', 'q_ok_v1'), question('q_ok', 'approved'));
    await setDoc(doc(db, 'courses', COURSE, 'questions', 'q_draft_v1'), question('q_draft', 'pending_review'));
    await setDoc(doc(db, 'courses', COURSE, 'answer_keys', 'q_ok_v1'), {
      question_id: 'q_ok', question_version: 1, correct_option_id: 'a',
    });
    await setDoc(doc(db, 'sessions', CODE), {
      code: CODE,
      course_id: COURSE,
      owner_id: 'teacher',
      questions: [{ question_id: 'q_ok', version: 1 }],
      question_keys: ['q_ok_v1'],
      status: 'open',
      feedback_released: false,
    });
  });
});

const closeSession = () =>
  env.withSecurityRulesDisabled((ctx) =>
    updateDoc(doc(ctx.firestore(), 'sessions', CODE), { status: 'closed' }));

describe('approved instructors', () => {
  test('an account not in the list is not an instructor', async () => {
    const db = unapproved();
    await assertFails(setDoc(doc(db, 'courses', 'mine'), { owner_id: 'stranger' }));
    await assertFails(getDocs(query(collection(db, 'courses'), where('owner_id', '==', 'stranger'))));
    await assertFails(getDoc(doc(db, 'courses', COURSE, 'answer_keys', 'q_ok_v1')));
    await assertFails(getDocs(query(collection(db, 'sessions'), where('owner_id', '==', 'stranger'))));
  });

  test('a removed instructor loses access to their own course', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      deleteDoc(doc(ctx.firestore(), 'instructors', 'teacher')));
    await assertFails(getDoc(doc(instructor(), 'courses', COURSE, 'answer_keys', 'q_ok_v1')));
    await assertFails(updateDoc(doc(instructor(), 'sessions', CODE), { status: 'closed' }));
  });

  test('users check only their own entry', async () => {
    await assertSucceeds(getDoc(doc(instructor(), 'instructors', 'teacher')));
    await assertSucceeds(getDoc(doc(unapproved(), 'instructors', 'stranger')));
    await assertFails(getDoc(doc(unapproved(), 'instructors', 'teacher')));
    await assertFails(getDocs(collection(instructor(), 'instructors')));
    await assertFails(getDoc(doc(nobody(), 'instructors', 'teacher')));
  });

  test('nobody approves themselves from the app', async () => {
    await assertFails(setDoc(doc(unapproved(), 'instructors', 'stranger'), { email: 'x' }));
    await assertFails(setDoc(doc(student(), 'instructors', 'student1'), { email: 'x' }));
    await assertFails(updateDoc(doc(instructor(), 'instructors', 'teacher'), { role: 'admin' }));
    await assertFails(setDoc(doc(instructor(), 'instructors', 'teacher3'), { email: 'x' }));
    await assertFails(deleteDoc(doc(instructor(), 'instructors', 'teacher2')));
  });

  test('a large batch by the owner stays within the rules lookup limit', async () => {
    const db = instructor();
    const batch = writeBatch(db);
    for (let i = 0; i < 40; i++) {
      batch.set(doc(db, 'courses', COURSE, 'questions', `bulk${i}_v1`), question(`bulk${i}`, 'pending_review'));
      batch.set(doc(db, 'courses', COURSE, 'answer_keys', `bulk${i}_v1`), {
        question_id: `bulk${i}`, question_version: 1, correct_option_id: 'a',
      });
    }
    await assertSucceeds(batch.commit());
  });
});

describe('past sessions', () => {
  test('the owner creates a titled session and lists their sessions of a course', async () => {
    await assertSucceeds(setDoc(doc(instructor(), 'sessions', 'NEW234'), {
      code: 'NEW234', course_id: COURSE, owner_id: 'teacher',
      questions: [{ question_id: 'q_ok', version: 1 }], question_keys: ['q_ok_v1'],
      status: 'open', feedback_released: false,
      title: { ar: 'المفتاح الأساسي', en: 'Primary Key' },
      created_at: serverTimestamp(),
    }));
    const list = (db, owner) => getDocs(query(collection(db, 'sessions'),
      where('owner_id', '==', owner), where('course_id', '==', COURSE)));
    const mine = await assertSucceeds(list(instructor(), 'teacher'));
    if (mine.size !== 2) throw new Error('expected 2 sessions, got ' + mine.size);
    await assertFails(list(otherInstructor(), 'teacher'));
    await assertFails(list(student(), 'teacher'));
  });

  test('the owner renames a session; only a short {ar, en} title', async () => {
    const ref = (db) => doc(db, 'sessions', CODE);
    await assertSucceeds(updateDoc(ref(instructor()), {
      title: { ar: 'مراجعة المفاتيح', en: 'Keys review' },
    }));
    await assertFails(updateDoc(ref(instructor()), { title: { ar: 'x'.repeat(121), en: 'x' } }));
    await assertFails(updateDoc(ref(instructor()), { title: { ar: 'x', en: 'x', note: 'y' } }));
    await assertFails(updateDoc(ref(instructor()), { title: { ar: 1, en: 'x' } }));
    await assertFails(updateDoc(ref(instructor()), { title: 'plain text' }));
    // Renaming does not open the door to other fields.
    await assertFails(updateDoc(ref(instructor()), { title: { ar: 'a', en: 'b' }, owner_id: 'teacher2' }));
  });

  test('nobody else renames it', async () => {
    const t = { title: { ar: 'x', en: 'x' } };
    await assertFails(updateDoc(doc(otherInstructor(), 'sessions', CODE), t));
    await assertFails(updateDoc(doc(student(), 'sessions', CODE), t));
    await assertFails(updateDoc(doc(nobody(), 'sessions', CODE), t));
  });
});

describe('resuming an open session', () => {
  test('the owner finds their open sessions of a course; others cannot', async () => {
    const q = (db, owner) => query(collection(db, 'sessions'),
      where('owner_id', '==', owner), where('course_id', '==', COURSE),
      where('status', '==', 'open'));
    const mine = await assertSucceeds(getDocs(q(instructor(), 'teacher')));
    if (mine.docs.map((d) => d.id).join() !== CODE) throw new Error('expected ' + CODE);
    await assertFails(getDocs(q(otherInstructor(), 'teacher')));
    await assertFails(getDocs(q(student(), 'teacher')));
  });
});

describe('course content', () => {
  test('signed-out users read nothing', async () => {
    await assertFails(getDoc(doc(nobody(), 'courses', COURSE)));
    await assertFails(getDoc(doc(nobody(), 'courses', COURSE, 'questions', 'q_ok_v1')));
  });

  test('students read approved questions only', async () => {
    await assertSucceeds(getDoc(doc(student(), 'courses', COURSE, 'questions', 'q_ok_v1')));
    await assertFails(getDoc(doc(student(), 'courses', COURSE, 'questions', 'q_draft_v1')));
  });

  test('students cannot list questions', async () => {
    await assertFails(getDocs(collection(student(), 'courses', COURSE, 'questions')));
  });

  test('students never read answer keys', async () => {
    await assertFails(getDoc(doc(student(), 'courses', COURSE, 'answer_keys', 'q_ok_v1')));
    await assertFails(getDocs(collection(student(), 'courses', COURSE, 'answer_keys')));
  });

  test('the owner reads drafts and answer keys', async () => {
    await assertSucceeds(getDocs(collection(instructor(), 'courses', COURSE, 'questions')));
    await assertSucceeds(getDoc(doc(instructor(), 'courses', COURSE, 'answer_keys', 'q_ok_v1')));
  });

  test('another instructor cannot read keys or edit the course', async () => {
    await assertFails(getDoc(doc(otherInstructor(), 'courses', COURSE, 'answer_keys', 'q_ok_v1')));
    await assertFails(setDoc(doc(otherInstructor(), 'courses', COURSE, 'questions', 'x_v1'), question('x', 'approved')));
  });

  test('students cannot write content or approve drafts', async () => {
    await assertFails(updateDoc(doc(student(), 'courses', COURSE, 'questions', 'q_draft_v1'), {
      'provenance.status': 'approved',
    }));
    await assertFails(setDoc(doc(student(), 'courses', 'mine'), { owner_id: 'student1' }));
  });

  test('the owner approves a draft', async () => {
    await assertSucceeds(updateDoc(doc(instructor(), 'courses', COURSE, 'questions', 'q_draft_v1'), {
      'provenance.status': 'approved',
    }));
  });

  test('an instructor creates a course only in their own name', async () => {
    await assertSucceeds(setDoc(doc(otherInstructor(), 'courses', 'c2'), { owner_id: 'teacher2' }));
    await assertFails(setDoc(doc(otherInstructor(), 'courses', 'c3'), { owner_id: 'teacher' }));
  });

  test('an instructor lists only their own courses', async () => {
    await assertSucceeds(getDocs(query(collection(instructor(), 'courses'), where('owner_id', '==', 'teacher'))));
    await assertFails(getDocs(collection(instructor(), 'courses')));
  });
});

describe('sessions', () => {
  const newSession = (owner, courseId = COURSE) => ({
    code: 'XYZ789', course_id: courseId, owner_id: owner,
    questions: [], question_keys: [], status: 'open', feedback_released: false,
  });

  test('a student who knows the code reads the session', async () => {
    await assertSucceeds(getDoc(doc(student(), 'sessions', CODE)));
  });

  test('sessions cannot be listed to guess codes', async () => {
    await assertFails(getDocs(collection(student(), 'sessions')));
    await assertFails(getDocs(query(collection(student(), 'sessions'), limit(1))));
  });

  test('only the course owner creates a session for it', async () => {
    await assertSucceeds(setDoc(doc(instructor(), 'sessions', 'XYZ789'), newSession('teacher')));
    await assertFails(setDoc(doc(otherInstructor(), 'sessions', 'XYZ789'), newSession('teacher2')));
    await assertFails(setDoc(doc(student(), 'sessions', 'XYZ789'), newSession('student1')));
  });

  test('an existing code cannot be taken over', async () => {
    await assertFails(setDoc(doc(otherInstructor(), 'sessions', CODE), newSession('teacher2')));
  });

  test('the owner closes and releases feedback; nothing else changes', async () => {
    await assertSucceeds(updateDoc(doc(instructor(), 'sessions', CODE), { status: 'closed' }));
    await assertSucceeds(updateDoc(doc(instructor(), 'sessions', CODE), { feedback_released: true }));
    await assertFails(updateDoc(doc(instructor(), 'sessions', CODE), { question_keys: ['q_draft_v1'] }));
    await assertFails(updateDoc(doc(student(), 'sessions', CODE), { status: 'closed' }));
  });

  test('sessions are never deleted from the client', async () => {
    await assertFails(deleteDoc(doc(instructor(), 'sessions', CODE)));
  });
});

describe('participants', () => {
  test('a student joins as themselves only, while open', async () => {
    await assertSucceeds(setDoc(doc(student(), 'sessions', CODE, 'participants', 'student1'), { joined_at: serverTimestamp() }));
    await assertFails(setDoc(doc(student(), 'sessions', CODE, 'participants', 'student2'), { joined_at: serverTimestamp() }));
    await closeSession();
    await assertFails(setDoc(doc(student('student3'), 'sessions', CODE, 'participants', 'student3'), { joined_at: serverTimestamp() }));
  });

  test('students cannot list other participants', async () => {
    await assertFails(getDocs(collection(student(), 'sessions', CODE, 'participants')));
  });
});

describe('responses', () => {
  const rid = (uid, q = 'q_ok') => `${uid}_${q}_v1`;

  test('a student answers a question of the session once', async () => {
    const db = student();
    await assertSucceeds(setDoc(doc(db, 'sessions', CODE, 'responses', rid('student1')), response('student1')));
    // A second write is an update and is refused.
    await assertFails(setDoc(doc(db, 'sessions', CODE, 'responses', rid('student1')), response('student1', { selected_option_id: 'b' })));
  });

  test('a student cannot answer for someone else', async () => {
    await assertFails(setDoc(doc(student(), 'sessions', CODE, 'responses', rid('student2')), response('student2')));
    await assertFails(setDoc(doc(student(), 'sessions', CODE, 'responses', rid('student2')), response('student1')));
  });

  test('questions outside the session are refused', async () => {
    await assertFails(setDoc(
      doc(student(), 'sessions', CODE, 'responses', rid('student1', 'q_draft')),
      response('student1', { question_id: 'q_draft' })));
  });

  test('answers after closing are refused', async () => {
    await closeSession();
    await assertFails(setDoc(doc(student(), 'sessions', CODE, 'responses', rid('student1')), response('student1')));
  });

  test('extra fields, bad languages and client timestamps are refused', async () => {
    const ref = doc(student(), 'sessions', CODE, 'responses', rid('student1'));
    await assertFails(setDoc(ref, response('student1', { correct: true })));
    await assertFails(setDoc(ref, response('student1', { display_language: 'fr' })));
    await assertFails(setDoc(ref, response('student1', { submitted_at: new Date(0) })));
  });

  test('Arabic and English answers are stored the same way', async () => {
    await assertSucceeds(setDoc(doc(student('s_ar'), 'sessions', CODE, 'responses', rid('s_ar')), response('s_ar', { display_language: 'ar' })));
    await assertSucceeds(setDoc(doc(student('s_en'), 'sessions', CODE, 'responses', rid('s_en')), response('s_en', { display_language: 'en' })));
  });

  test("students read their own answer only; the owner reads all", async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'sessions', CODE, 'responses', rid('student2')), response('student2')));
    await assertFails(getDoc(doc(student(), 'sessions', CODE, 'responses', rid('student2'))));
    await assertFails(getDocs(collection(student(), 'sessions', CODE, 'responses')));
    await assertSucceeds(getDoc(doc(student('student2'), 'sessions', CODE, 'responses', rid('student2'))));
    await assertSucceeds(getDocs(collection(instructor(), 'sessions', CODE, 'responses')));
    await assertFails(getDocs(collection(otherInstructor(), 'sessions', CODE, 'responses')));
  });
});

describe('feedback and aggregates', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), 'sessions', CODE, 'feedback', 'student1'), { concepts: [] }));
  });

  test('a student sees their feedback only after release', async () => {
    await assertFails(getDoc(doc(student(), 'sessions', CODE, 'feedback', 'student1')));
    await updateDoc(doc(instructor(), 'sessions', CODE), { feedback_released: true });
    await assertSucceeds(getDoc(doc(student(), 'sessions', CODE, 'feedback', 'student1')));
    await assertFails(getDoc(doc(student('student2'), 'sessions', CODE, 'feedback', 'student1')));
  });

  test('aggregates are for the owner only', async () => {
    await assertSucceeds(setDoc(doc(instructor(), 'sessions', CODE, 'aggregates', 'summary'), { n: 1 }));
    await assertFails(getDoc(doc(student(), 'sessions', CODE, 'aggregates', 'summary')));
  });
});
