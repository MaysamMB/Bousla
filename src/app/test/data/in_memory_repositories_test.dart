import 'dart:math';

import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/join_code.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Response _r(
  String participant,
  String question,
  String option, {
  int version = 1,
}) => Response(
  participantId: participant,
  questionId: question,
  questionVersion: version,
  selectedOptionId: option,
  displayLanguage: Language.ar,
);

void main() {
  group('join codes', () {
    test('have the expected length and only unambiguous characters', () {
      final rng = Random(1);
      for (var i = 0; i < 200; i++) {
        final code = generateJoinCode(rng);
        expect(code.length, equals(joinCodeLength));
        expect(code.split('').every(joinCodeAlphabet.contains), isTrue);
      }
    });

    test('normalize lowercase, spaces and dashes', () {
      expect(normalizeJoinCode(' ab c-d23 '), equals('ABCD23'));
    });
  });

  group('InMemoryContentRepository', () {
    final repo = InMemoryContentRepository();

    test('loads the bilingual sample course', () async {
      final courses = await repo.listCourses();
      expect(
        courses.single.name.of(Language.ar),
        equals('أنظمة قواعد البيانات'),
      );
      final questions = await repo.listQuestions('database_systems');
      expect(questions, hasLength(4));
      expect(
        questions.first.options.first.text.of(Language.en),
        equals('Unique and not NULL'),
      );
    });

    test(
      'every sample question has a key that matches one of its options',
      () async {
        final questions = await repo.listQuestions('database_systems');
        final keys = await repo.answerKeys('database_systems');
        for (final q in questions) {
          final key = keys.where((k) => k.questionId == q.id).single;
          expect(
            q.options.map((o) => o.id).contains(key.correctOptionId),
            isTrue,
          );
        }
      },
    );

    test('unknown course returns nothing', () async {
      expect(await repo.listQuestions('nope'), isEmpty);
      expect(await repo.answerKeys('nope'), isEmpty);
    });
  });

  group('InMemorySessionRepository', () {
    late InMemorySessionRepository repo;
    late Session session;

    setUp(() async {
      repo = InMemorySessionRepository(random: Random(7));
      session = await repo.createSession(
        courseId: 'database_systems',
        ownerId: 'teacher',
        questions: const [QuestionRef('db_pk_001', 1)],
      );
    });

    test('new session is open, with a join code, feedback not released', () {
      expect(session.status, equals(SessionStatus.open));
      expect(session.code.length, equals(joinCodeLength));
      expect(session.feedbackReleased, isFalse);
    });

    test('find by code ignores case and spaces', () async {
      final found = await repo.findByCode(' ${session.code.toLowerCase()} ');
      expect(found?.id, equals(session.id));
      expect(await repo.findByCode('ZZZZZZ'), isNull);
    });

    test('join gives different participant IDs', () async {
      final a = await repo.join(session.id);
      final b = await repo.join(session.id);
      expect(a == b, isFalse);
    });

    test('responses are streamed to the instructor', () async {
      final updates = <int>[];
      final sub = repo
          .watchResponses(session.id)
          .listen((rs) => updates.add(rs.length));
      await repo.submitResponse(session.id, _r('p1', 'db_pk_001', 'a'));
      await repo.submitResponse(session.id, _r('p2', 'db_pk_001', 'b'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(updates, equals([0, 1, 2]));
    });

    test('second answer to the same question is rejected', () async {
      await repo.submitResponse(session.id, _r('p1', 'db_pk_001', 'a'));
      Object? error;
      try {
        await repo.submitResponse(session.id, _r('p1', 'db_pk_001', 'b'));
      } catch (e) {
        error = e;
      }
      expect(error is DuplicateAnswerException, isTrue);
    });

    test('answers after closing are rejected', () async {
      await repo.closeSession(session.id);
      Object? error;
      try {
        await repo.submitResponse(session.id, _r('p1', 'db_pk_001', 'a'));
      } catch (e) {
        error = e;
      }
      expect(error is SessionClosedException, isTrue);
    });

    test('closing and releasing feedback are visible to watchers', () async {
      final seen = <String>[];
      final sub = repo
          .watchSession(session.id)
          .listen((s) => seen.add('${s.status.name}/${s.feedbackReleased}'));
      await repo.closeSession(session.id);
      await repo.releaseFeedback(session.id);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, equals(['open/false', 'closed/false', 'closed/true']));
    });

    test(
      'sample content and session responses run through the engine',
      () async {
        final content = InMemoryContentRepository();
        final questions = await content.listQuestions('database_systems');
        await repo.submitResponse(session.id, _r('p1', 'db_pk_001', 'a'));
        final responses = await repo.watchResponses(session.id).first;
        final result = scoreResponses(
          responses: responses,
          questions: questions.map((q) => q.question),
          keys: await content.answerKeys('database_systems'),
        );
        expect(result.scored.single.isCorrect, isTrue);
      },
    );
  });
}
