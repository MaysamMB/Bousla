import 'dart:typed_data';

import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/firebase/firestore_codec.dart';
import 'package:bousla_app/data/firebase/firestore_content_repository.dart';
import 'package:bousla_app/data/fake/sample_content.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/question_review.dart';
import 'package:bousla_app/features/instructor/content_review/content_review_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

GeneratedQuestion _g(
  String en, {
  List<String> concepts = const ['primary_key'],
  String ar = 'هل يقبل المفتاح الأساسي (Primary Key) القيمة NULL؟',
}) =>
    GeneratedQuestion(
      conceptIds: concepts,
      prompt: LocalizedText(ar: ar, en: en),
      options: const [
        GeneratedOption(id: 'a', text: LocalizedText(ar: 'نعم', en: 'Yes')),
        GeneratedOption(id: 'b', text: LocalizedText(ar: 'لا', en: 'No')),
      ],
      correctOptionId: 'b',
      sourceLocation: 'page 4',
      difficulty: 'basic',
    );

/// Fixed answer instead of calling Gemini.
class _FakeGenerator implements QuestionGenerator {
  _FakeGenerator({this.result, this.error});

  final DraftParseResult? result;
  final QuestionGenerationException? error;
  MaterialFile? lastMaterial;
  int? lastCount;

  @override
  String get modelName => 'fake-model';

  @override
  Future<DraftParseResult> draftQuestions({
    required MaterialFile material,
    required List<Concept> concepts,
    required int count,
  }) async {
    lastMaterial = material;
    lastCount = count;
    if (error != null) throw error!;
    return result!;
  }
}

final _pdf = MaterialFile(
  name: 'lecture03.pdf',
  mimeType: 'application/pdf',
  bytes: Uint8List.fromList(List.filled(2048, 1)),
);

void main() {
  test('MaterialFile accepts PDF and text only', () {
    expect(MaterialFile.mimeTypeFor('Lecture.PDF'), 'application/pdf');
    expect(MaterialFile.mimeTypeFor('notes.md'), 'text/plain');
    expect(MaterialFile.mimeTypeFor('slides.pptx'), isNull);
  });

  group('saveAiDrafts (in memory)', () {
    test(
        'drafts wait for review, with key and source; students do not see them',
        () async {
      final repo = InMemoryContentRepository();
      final saved = await repo.saveAiDrafts(
        _course,
        materialName: 'lecture03.pdf',
        modelName: 'fake-model',
        drafts: [_g('Can a primary key be NULL?')],
        droppedByChecks: 2,
      );
      final q = saved.single;
      expect(q.source, ContentSource.aiDraft);
      expect(q.status, ReviewStatus.pendingReview);
      expect(q.sourceLocation, 'page 4');
      expect(q.edited, isFalse);
      final keys = await repo.answerKeys(_course);
      expect(
          keys.where((k) => k.questionId == q.id).single.correctOptionId, 'b');
      expect((await repo.listQuestions(_course)).map((x) => x.id),
          isNot(contains(q.id)));
      expect(repo.materials.single['drafts_dropped'], 2);
      // Counted in the AI draft statistics.
      final stats =
          aiReviewStats(await repo.listQuestions(_course, approvedOnly: false));
      expect(stats.pending, greaterThanOrEqualTo(1));
    });

    test('drafts failing the checks (unknown concept) are skipped and counted',
        () async {
      final repo = InMemoryContentRepository();
      final saved = await repo.saveAiDrafts(
        _course,
        materialName: 'm.txt',
        modelName: 'fake-model',
        drafts: [
          _g('OK question?'),
          _g('Bad concept?', concepts: const ['no_such'])
        ],
      );
      expect(saved, hasLength(1));
      expect(repo.materials.single['drafts_dropped'], 1);
    });
  });

  group('saveAiDrafts (Firestore)', () {
    test('saves questions, keys and a material record without the file',
        () async {
      final db = FakeFirebaseFirestore();
      final course = db.collection('courses').doc(_course);
      await course.set({'name': sampleCourse['name'], 'owner_id': 'teacher'});
      for (final c in sampleConcepts) {
        await course.collection('concepts').doc(c['id'] as String).set(c);
      }
      final repo =
          FirestoreContentRepository(db, currentUserId: () => 'teacher');
      final saved = await repo.saveAiDrafts(
        _course,
        materialName: 'lecture03.pdf',
        modelName: 'fake-model',
        drafts: [_g('Can a primary key be NULL?')],
        droppedByChecks: 1,
      );
      final id = saved.single.id;
      expect(id, startsWith('ai_q_'));
      final doc =
          await course.collection('questions').doc(questionDocId(id, 1)).get();
      final provenance = doc.data()!['provenance'] as Map;
      expect(provenance['source'], 'ai_draft');
      expect(provenance['status'], 'pending_review');
      expect(provenance['source_location'], 'page 4');
      expect(provenance['generated_by'], 'fake-model');
      expect(provenance['source_material_id'], startsWith('mat_'));
      expect(doc.data()!['difficulty'], 'basic');
      final key = await course
          .collection('answer_keys')
          .doc(questionDocId(id, 1))
          .get();
      expect(key.data()!['correct_option_id'], 'b');
      final material =
          (await course.collection('materials').get()).docs.single.data();
      expect(material['file_name'], 'lecture03.pdf');
      expect(material['drafts_saved'], 1);
      expect(material['drafts_dropped'], 1);
      expect(material.containsKey('bytes'), isFalse);
      // The instructor sees it in review; it reads back as an AI draft.
      final all = await repo.listQuestions(_course, approvedOnly: false);
      expect(all.where((q) => q.id == id).single.source, ContentSource.aiDraft);
    });
  });

  group('review screen', () {
    Future<InMemoryContentRepository> open(
      WidgetTester tester,
      QuestionGenerator? generator,
    ) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final content = InMemoryContentRepository();
      await tester.pumpWidget(
        ServicesScope(
          services: AppServices(
            content: content,
            sessions: InMemorySessionRepository(),
            questionGenerator: generator,
          ),
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ContentReviewScreen(pickMaterial: () async => _pdf),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return content;
    }

    testWidgets('no AI button when no generator is configured', (tester) async {
      await open(tester, null);
      expect(find.text('Draft questions from material (AI)'), findsNothing);
    });

    testWidgets('AI drafts from a file appear in "waiting" with their source', (
      tester,
    ) async {
      final generator = _FakeGenerator(
        result: DraftParseResult(
          accepted: [_g('Can a primary key be NULL?')],
          dropped: const [DraftIssue.unknownConcept],
        ),
      );
      final content = await open(tester, generator);
      await tester.tap(find.text('Draft questions from material (AI)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('It is not stored'), findsOneWidget);
      // Nothing is sent before a file is chosen.
      final start = find.widgetWithText(FilledButton, 'Draft questions');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);

      await tester.tap(find.text('Choose a file (PDF or text)'));
      await tester.pumpAndSettle();
      expect(find.text('lecture03.pdf · 2 KB'), findsOneWidget);
      await tester.tap(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(generator.lastMaterial?.name, 'lecture03.pdf');
      expect(generator.lastCount, 10);
      expect(
        find.text(
            '1 AI drafts are waiting for your review. 1 were dropped by the automatic checks.'),
        findsOneWidget,
      );
      expect(find.text('Can a primary key be NULL?'), findsOneWidget);
      // The new suggestions come first, under their own heading.
      expect(find.text('New AI suggestions (1)'), findsOneWidget);
      expect(find.textContaining('From «lecture03.pdf» · fake-model'),
          findsOneWidget);
      expect(find.text('Earlier drafts waiting for review'), findsOneWidget);
      final newHeading = tester.getTopLeft(find.text('New AI suggestions (1)'));
      final newDraft = tester.getTopLeft(find.text('Can a primary key be NULL?'));
      final earlier =
          tester.getTopLeft(find.text('Earlier drafts waiting for review'));
      expect(newHeading.dy, lessThan(newDraft.dy));
      expect(newDraft.dy, lessThan(earlier.dy));
      expect(find.text('From the material: page 4'), findsWidgets);
      // Still a draft: students cannot get it.
      final forStudents = await content.listQuestions(_course);
      expect(
          forStudents.any((q) =>
              q.source == ContentSource.aiDraft &&
              q.prompt.en == 'Can a primary key be NULL?'),
          isFalse);
    });

    testWidgets('a setup problem is explained in the dialog', (tester) async {
      await open(
        tester,
        _FakeGenerator(
          error: const QuestionGenerationException(
            GenerationProblem.notEnabled,
            'PERMISSION_DENIED: Caller does not have required permission',
          ),
        ),
      );
      await tester.tap(find.text('Draft questions from material (AI)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a file (PDF or text)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Draft questions'));
      await tester.pumpAndSettle();
      expect(find.textContaining('AI is not enabled for this Firebase project'),
          findsOneWidget);
      // The server's own reason is shown too, for diagnosis.
      expect(find.textContaining('PERMISSION_DENIED'), findsOneWidget);
    });
  });
}
