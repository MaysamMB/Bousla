// The optional personal profile: the same behaviour in memory and on
// (fake) Firestore. Access control is in firebase/firestore.rules and is
// tested on the emulator (rules.test.mjs, "personal profiles").
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/firebase/firestore_profile_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/profile_repository.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Session _session(String code) => Session(
      id: code,
      code: code,
      courseId: 'database_systems',
      ownerId: 'teacher',
      questions: const [],
      status: SessionStatus.closed,
      feedbackReleased: true,
      title: const LocalizedText(ar: 'المفاتيح', en: 'Keys'),
    );

const _feedback = StudentFeedback(
  language: Language.ar,
  concepts: [
    FeedbackConcept(
      conceptId: 'primary_key',
      name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
      state: MasteryState.emerging,
      attempts: 2,
      correct: 1,
    ),
  ],
);

void main() {
  for (final (name, make) in [
    ('in memory', () => InMemoryProfileRepository() as ProfileRepository),
    ('Firestore', () => FirestoreProfileRepository(FakeFirebaseFirestore()) as ProfileRepository),
  ]) {
    group('$name profile', () {
      test('no profile until the student agrees', () async {
        final repo = make();
        expect(await repo.consentVersion('s1'), isNull);
        await repo.create('s1');
        expect(await repo.consentVersion('s1'), profileConsentVersion);
      });

      test('saved sessions keep the concept states and evidence', () async {
        final repo = make();
        await repo.create('s1');
        await repo.saveSession('s1', _session('AAA222'), _feedback);
        await repo.saveSession('s1', _session('BBB333'), _feedback);
        expect(await repo.hasSession('s1', 'AAA222'), isTrue);
        final list = await repo.sessions('s1');
        expect(list.map((s) => s.code), containsAll(['AAA222', 'BBB333']));
        final c = list.first.concepts.single;
        expect(c.conceptId, 'primary_key');
        expect(c.name.ar, 'المفتاح الأساسي');
        expect(c.state, MasteryState.emerging);
        expect((c.correct, c.attempts), (1, 2));
        expect(list.first.title!.en, 'Keys');
        // Another student's profile is separate.
        expect(await repo.sessions('s2'), isEmpty);
      });

      test('saving a session that is already saved is not an error', () async {
        // The rules allow no edits; a retry after a half-finished save
        // must not fail.
        final repo = make();
        await repo.create('s1');
        await repo.saveSession('s1', _session('AAA222'), _feedback);
        await repo.saveSession('s1', _session('AAA222'), _feedback);
        expect((await repo.sessions('s1')).map((s) => s.code), ['AAA222']);
      });

      test('remove one session, then delete everything', () async {
        final repo = make();
        await repo.create('s1');
        await repo.saveSession('s1', _session('AAA222'), _feedback);
        await repo.saveSession('s1', _session('BBB333'), _feedback);
        await repo.removeSession('s1', 'AAA222');
        expect((await repo.sessions('s1')).map((s) => s.code), ['BBB333']);
        await repo.delete('s1');
        expect(await repo.sessions('s1'), isEmpty);
        expect(await repo.consentVersion('s1'), isNull);
      });
    });
  }
}
