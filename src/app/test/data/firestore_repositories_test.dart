// Firestore repositories against an in-memory fake Firestore. The fake does
// not enforce security rules; those are tested on the emulator in
// firebase/test/rules.test.mjs.
import 'dart:math';

import 'package:bousla_app/data/fake/sample_content.dart';
import 'package:bousla_app/data/firebase/firestore_codec.dart';
import 'package:bousla_app/data/firebase/firestore_content_repository.dart';
import 'package:bousla_app/data/firebase/firestore_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';
const _teacher = 'teacher';

/// Loads the sample course the way firebase/tools/seed.mjs does.
Future<void> _seed(FakeFirebaseFirestore db) async {
  final course = db.collection('courses').doc(_course);
  await course.set({'name': sampleCourse['name'], 'owner_id': _teacher});
  for (final c in sampleConcepts) {
    await course.collection('concepts').doc(c['id'] as String).set(c);
  }
  for (final q in sampleQuestions) {
    await course
        .collection('questions')
        .doc(questionDocId(q['id'] as String, q['version'] as int))
        .set(q);
  }
  for (final k in AnswerKey.listFromJson(sampleAnswerKeys)) {
    await course
        .collection('answer_keys')
        .doc(questionDocId(k.questionId, k.questionVersion))
        .set(answerKeyToJson(
            k.questionId, k.questionVersion, k.correctOptionId));
  }
  for (final r in sampleResources) {
    await course.collection('resources').doc(r['id'] as String).set(r);
  }
}

OptionView _o(String id, String ar, String en) =>
    OptionView(id: id, text: LocalizedText(ar: ar, en: en));

QuestionDraft _draft(
        {String? id,
        String correct = 'b',
        String en = 'Can a primary key be NULL?'}) =>
    QuestionDraft(
      id: id,
      conceptIds: const ['primary_key'],
      prompt: LocalizedText(
          ar: 'هل يقبل المفتاح الأساسي (Primary Key) القيمة الفارغة؟', en: en),
      options: [_o('a', 'نعم', 'Yes'), _o('b', 'لا', 'No')],
      correctOptionId: correct,
    );

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreContentRepository content;
  String? uid = _teacher;

  setUp(() async {
    db = FakeFirebaseFirestore();
    uid = _teacher;
    content = FirestoreContentRepository(db, currentUserId: () => uid);
    await _seed(db);
  });

  QuestionView find(List<QuestionView> qs, String id) =>
      qs.where((q) => q.id == id).single;

  group('FirestoreContentRepository', () {
    test('lists only the signed-in instructor\'s courses', () async {
      expect((await content.listCourses()).single.id, _course);
      uid = 'someone_else';
      expect(await content.listCourses(), isEmpty);
      uid = null;
      expect(await content.listCourses(), isEmpty);
    });

    test('reads bilingual questions; students get approved ones only',
        () async {
      final approved = await content.listQuestions(_course);
      final all = await content.listQuestions(_course, approvedOnly: false);
      expect(approved.every((q) => q.status == ReviewStatus.approved), isTrue);
      expect(all.length, greaterThan(approved.length));
      final pk = find(all, 'db_pk_001');
      expect(pk.prompt.ar, contains('المفتاح الأساسي'));
      expect(pk.prompt.en, contains('primary key'));
    });

    test('answer keys come back per question version', () async {
      final keys = await content.answerKeys(_course);
      expect(keys.length, sampleAnswerKeys.length);
      expect(keys.every((k) => k.questionVersion == 1), isTrue);
    });

    test('approving a draft makes it available, with the reviewer', () async {
      await content.setQuestionsStatus(
          _course, ['db_rm_001'], ReviewStatus.approved);
      expect(find(await content.listQuestions(_course), 'db_rm_001').status,
          ReviewStatus.approved);
      final doc = await db.doc('courses/$_course/questions/db_rm_001_v1').get();
      expect(doc.data()!['provenance']['reviewed_by'], _teacher);
      // Fields the app does not model survive.
      expect(doc.data()!['provenance']['source'], 'ai_draft');
    });

    test('rejecting keeps the reason; restoring clears it', () async {
      await content.setQuestionsStatus(
          _course, ['db_rm_001'], ReviewStatus.rejected,
          reason: RejectionReason.offTopic);
      var q = find(await content.listQuestions(_course, approvedOnly: false),
          'db_rm_001');
      expect(q.status, ReviewStatus.rejected);
      expect(q.rejectionReason, RejectionReason.offTopic);
      await content.setQuestionsStatus(
          _course, ['db_rm_001'], ReviewStatus.pendingReview);
      q = find(await content.listQuestions(_course, approvedOnly: false),
          'db_rm_001');
      expect(q.rejectionReason, isNull);
    });

    test('adding a question by hand saves it and its key together', () async {
      final created = await content.saveQuestion(_course, _draft());
      expect(created.id, startsWith('instr_q_'));
      expect(created.source, ContentSource.instructor);
      expect(created.status, ReviewStatus.pendingReview);
      final keys = await content.answerKeys(_course);
      expect(
          keys.where((k) => k.questionId == created.id).single.correctOptionId,
          'b');
      // Arabic with an English technical term is stored unchanged.
      final stored = find(
          await content.listQuestions(_course, approvedOnly: false),
          created.id);
      expect(stored.prompt.ar, contains('(Primary Key)'));
    });

    test('editing an AI draft changes it in place and marks it edited',
        () async {
      final before = find(
          await content.listQuestions(_course, approvedOnly: false),
          'db_rm_001');
      final keys = await content.answerKeys(_course);
      final key =
          keys.where((k) => k.questionId == 'db_rm_001').single.correctOptionId;
      final draft = QuestionDraft.fromQuestion(before, key);
      await content.saveQuestion(
        _course,
        QuestionDraft(
          id: draft.id,
          conceptIds: draft.conceptIds,
          prompt: LocalizedText(
              ar: draft.prompt.ar, en: '${draft.prompt.en} (edited)'),
          options: draft.options,
          correctOptionId: draft.correctOptionId,
        ),
      );
      final after = find(
          await content.listQuestions(_course, approvedOnly: false),
          'db_rm_001');
      expect(after.version, before.version);
      expect(after.edited, isTrue);
    });

    test(
        'editing an approved question creates a new version; sessions keep the old one',
        () async {
      final created = await content.saveQuestion(_course, _draft(),
          status: ReviewStatus.approved);
      final edited = await content.saveQuestion(
        _course,
        _draft(
            id: created.id,
            correct: 'a',
            en: 'Can a primary key ever be NULL?'),
      );
      expect(edited.version, 2);
      expect(edited.status, ReviewStatus.approved);

      final old = await content
          .questionsForSession(_course, [QuestionRef(created.id, 1)]);
      expect(old.single.prompt.en, 'Can a primary key be NULL?');
      final keys = await content.answerKeys(_course);
      String keyFor(int v) => keys
          .where((k) => k.questionId == created.id && k.questionVersion == v)
          .single
          .correctOptionId;
      expect(keyFor(1), 'b');
      expect(keyFor(2), 'a');
    });

    test('saving unchanged keeps the version', () async {
      final created = await content.saveQuestion(_course, _draft(),
          status: ReviewStatus.approved);
      final again = await content.saveQuestion(_course, _draft(id: created.id));
      expect(again.version, 1);
    });

    test('questionsForSession skips questions rejected later', () async {
      await content.setQuestionsStatus(
          _course, ['db_pk_001'], ReviewStatus.rejected);
      final qs = await content.questionsForSession(_course, const [
        QuestionRef('db_pk_001', 1),
        QuestionRef('db_pk_002', 1),
        QuestionRef('missing', 1),
      ]);
      expect([for (final q in qs) q.id], ['db_pk_002']);
    });

    test('hiding a language applies to every version', () async {
      final created = await content.saveQuestion(_course, _draft(),
          status: ReviewStatus.approved);
      await content.saveQuestion(_course, _draft(id: created.id, correct: 'a'));
      await content.setOptionLanguageHidden(_course, [created.id], Language.ar,
          hidden: true);
      final v1 = (await content
              .questionsForSession(_course, [QuestionRef(created.id, 1)]))
          .single;
      final v2 = (await content
              .questionsForSession(_course, [QuestionRef(created.id, 2)]))
          .single;
      expect(v1.hiddenOptionLanguages, {Language.ar});
      expect(v2.hiddenOptionLanguages, {Language.ar});
      expect(v2.optionLanguageFor(Language.ar), Language.en);
      await content.setOptionLanguageHidden(_course, [created.id], Language.ar,
          hidden: false);
      expect(
        find(await content.listQuestions(_course), created.id)
            .hiddenOptionLanguages,
        isEmpty,
      );
    });

    test('invalid drafts and unknown questions are refused', () async {
      await expectLater(
        content.saveQuestion(
          _course,
          QuestionDraft(
            conceptIds: const ['unknown'],
            prompt: const LocalizedText(ar: 'no arabic', en: ''),
            options: const [],
            correctOptionId: null,
          ),
        ),
        throwsA(isA<InvalidDraftException>()),
      );
      await expectLater(
        content.saveQuestion(_course, _draft(id: 'nope')),
        throwsArgumentError,
      );
    });
  });

  group('FirestoreSessionRepository', () {
    late FirestoreSessionRepository sessions;
    late Session session;
    var nextStudent = 0;

    setUp(() async {
      nextStudent = 0;
      sessions = FirestoreSessionRepository(
        db,
        ensureParticipant: () async => 'student${++nextStudent}',
        random: Random(7),
      );
      session = await sessions.createSession(
        courseId: _course,
        ownerId: _teacher,
        questions: const [
          QuestionRef('db_pk_001', 1),
          QuestionRef('db_pk_002', 1)
        ],
      );
    });

    test('listSessions: titled sessions of the owner and course, newest first',
        () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final titled = await sessions.createSession(
        courseId: _course,
        ownerId: _teacher,
        questions: const [QuestionRef('db_pk_001', 1)],
        title: const LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
      );
      await sessions.closeSession(session.id);
      final list =
          await sessions.listSessions(ownerId: _teacher, courseId: _course);
      expect([for (final s in list) s.id], [titled.id, session.id]);
      expect(list.first.title?.ar, 'المفتاح الأساسي');
      expect(list.first.createdAt, isNotNull);
      expect(list.last.status, SessionStatus.closed);
      expect(list.last.closedAt, isNotNull);
      expect(list.last.title, isNull);
      expect(
        await sessions.listSessions(ownerId: 'other', courseId: _course),
        isEmpty,
      );
    });

    test('renameSession stores the new title', () async {
      await sessions.renameSession(
        session.id,
        const LocalizedText(ar: 'مراجعة', en: 'Review'),
      );
      final again = (await sessions.findByCode(session.code))!;
      expect((again.title?.ar, again.title?.en), ('مراجعة', 'Review'));
      expect(again.status, SessionStatus.open);
    });

    test('latestOpenSession: newest open session of the owner and course',
        () async {
      expect(
        (await sessions.latestOpenSession(ownerId: _teacher, courseId: _course))
            ?.id,
        session.id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await sessions.createSession(
        courseId: _course,
        ownerId: _teacher,
        questions: const [QuestionRef('db_pk_001', 1)],
      );
      expect(
        (await sessions.latestOpenSession(ownerId: _teacher, courseId: _course))
            ?.id,
        second.id,
      );
      await sessions.closeSession(second.id);
      expect(
        (await sessions.latestOpenSession(ownerId: _teacher, courseId: _course))
            ?.id,
        session.id,
      );
      expect(
        await sessions.latestOpenSession(ownerId: 'other', courseId: _course),
        isNull,
      );
      expect(
        await sessions.latestOpenSession(ownerId: _teacher, courseId: 'x'),
        isNull,
      );
    });

    Response answer(String participant,
            {String q = 'db_pk_001', Language lang = Language.ar}) =>
        Response(
          participantId: participant,
          questionId: q,
          questionVersion: 1,
          selectedOptionId: 'a',
          displayLanguage: lang,
        );

    test('the session document ID is the join code', () async {
      expect(session.id, session.code);
      expect(session.status, SessionStatus.open);
      final doc = await db.doc('sessions/${session.code}').get();
      expect(doc.data()!['question_keys'], ['db_pk_001_v1', 'db_pk_002_v1']);
      expect(doc.data()!['owner_id'], _teacher);
    });

    test('find by code ignores case, spaces and dashes; bad input is null',
        () async {
      final code = session.code;
      final messy =
          '${code.substring(0, 3).toLowerCase()}-${code.substring(3)} ';
      expect((await sessions.findByCode(messy))?.id, code);
      expect(await sessions.findByCode('ZZZZZZ'), isNull);
      expect(await sessions.findByCode('a/b'), isNull);
      expect(await sessions.findByCode(''), isNull);
    });

    test('looking up a code signs the student in first', () async {
      expect(nextStudent, 0);
      await sessions.findByCode(session.code);
      expect(nextStudent, 1);
    });

    test('two sessions get different codes', () async {
      final other = await sessions.createSession(
          courseId: _course, ownerId: _teacher, questions: const []);
      expect(other.code, isNot(session.code));
    });

    test('join registers the anonymous participant', () async {
      final id = await sessions.join(session.id);
      expect(id, 'student1');
      expect(
          (await db.doc('sessions/${session.id}/participants/student1').get())
              .exists,
          isTrue);
    });

    test('answers in Arabic and English reach the instructor', () async {
      final stream = sessions.watchResponses(session.id);
      await sessions.submitResponse(session.id, answer('s_ar'));
      await sessions.submitResponse(
          session.id, answer('s_en', lang: Language.en));
      final responses = await stream.firstWhere((r) => r.length == 2);
      expect({for (final r in responses) r.displayLanguage},
          {Language.ar, Language.en});
      final doc = await db
          .doc('sessions/${session.id}/responses/s_ar_db_pk_001_v1')
          .get();
      expect(doc.data()!['display_language'], 'ar');
      expect(doc.data()!['question_version'], 1);
    });

    test('a second answer to the same question is refused', () async {
      await sessions.submitResponse(session.id, answer('s1'));
      await expectLater(
        sessions.submitResponse(session.id, answer('s1')),
        throwsA(isA<DuplicateAnswerException>()),
      );
      await sessions.submitResponse(session.id, answer('s1', q: 'db_pk_002'));
    });

    test('answers after closing are refused; watchers see the change',
        () async {
      final closed = sessions
          .watchSession(session.id)
          .firstWhere((s) => s.status == SessionStatus.closed);
      await sessions.closeSession(session.id);
      expect((await closed).id, session.id);
      await expectLater(
        sessions.submitResponse(session.id, answer('s1')),
        throwsA(isA<SessionClosedException>()),
      );
    });

    test('answeredQuestions lists only this participant\'s answers', () async {
      await sessions.submitResponse(session.id, answer('s1'));
      await sessions.submitResponse(session.id, answer('s2', q: 'db_pk_002'));
      expect(await sessions.answeredQuestions(session, 's1'), {
        const QuestionRef('db_pk_001', 1),
      });
      expect(await sessions.answeredQuestions(session, 's3'), isEmpty);
    });

    test('releasing feedback is stored', () async {
      await sessions.releaseFeedback(session.id);
      expect(
          (await sessions.findByCode(session.code))!.feedbackReleased, isTrue);
    });

    test('Firestore responses run through the engine like in-memory ones',
        () async {
      await sessions.submitResponse(session.id, answer('s1'));
      await sessions.submitResponse(
          session.id, answer('s2', lang: Language.en));
      final responses = await sessions.watchResponses(session.id).first;
      final keys = await content.answerKeys(_course);
      final questions =
          await content.questionsForSession(_course, session.questions);
      final scored = scoreResponses(
        responses: responses,
        questions: [for (final q in questions) q.question],
        keys: keys,
      );
      expect(scored.ignored, isEmpty);
      // Same option in AR and EN → same result.
      expect(scored.scored.map((s) => s.isCorrect).toSet().length, 1);
    });
  });
}
