import 'dart:typed_data';

import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/features/student_web/knowledge_map/knowledge_map_layout.dart';
import 'package:bousla_app/features/student_web/knowledge_map/knowledge_map_view.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

FeedbackConcept _c(
  String id,
  MasteryState state, {
  List<String> prerequisites = const [],
  int attempts = 2,
  int correct = 0,
}) =>
    FeedbackConcept(
      conceptId: id,
      name: LocalizedText(ar: 'مفهوم $id', en: 'Concept $id'),
      state: state,
      attempts: attempts,
      correct: correct,
      prerequisites: prerequisites,
    );

final _feedback = StudentFeedback(
  language: Language.ar,
  concepts: [
    _c('fk', MasteryState.possibleDifficulty, prerequisites: ['pk']),
    _c('pk', MasteryState.possibleDifficulty),
    _c('rel', MasteryState.demonstratedMastery, attempts: 3, correct: 3),
    _c('join', MasteryState.insufficientEvidence,
        prerequisites: ['fk', 'rel'], attempts: 0),
  ],
  hints: const [
    FeedbackHint(
      conceptId: 'fk',
      prerequisiteId: 'pk',
      signal: PrerequisiteSignal.possibleContributingGap,
    ),
  ],
);

Future<void> _show(
  WidgetTester tester,
  Locale locale, {
  SaveImage? save,
  Size size = const Size(400, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: save == null
              ? KnowledgeMapView(feedback: _feedback)
              : KnowledgeMapView(feedback: _feedback, saveImage: save),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('knowledgeMapLevels', () {
    List<List<String>> ids(List<FeedbackConcept> cs) => [
          for (final level in knowledgeMapLevels(cs))
            [for (final c in level) c.conceptId],
        ];

    test('foundations first, each concept after its deepest prerequisite', () {
      expect(ids(_feedback.concepts), [
        ['pk', 'rel'],
        ['fk'],
        ['join'],
      ]);
    });

    test('a prerequisite outside the session is ignored', () {
      expect(
        ids([
          _c('fk', MasteryState.emerging, prerequisites: ['not_in_session']),
        ]),
        [
          ['fk'],
        ],
      );
    });

    test('a cycle in the data does not loop', () {
      final levels = ids([
        _c('a', MasteryState.emerging, prerequisites: ['b']),
        _c('b', MasteryState.emerging, prerequisites: ['a']),
      ]);
      expect(levels.expand((l) => l).toSet(), {'a', 'b'});
    });

    test('empty session', () {
      expect(knowledgeMapLevels(const []), isEmpty);
    });
  });

  group('FeedbackConcept', () {
    test('keeps prerequisites in JSON; older documents read as none', () {
      final c = _c('fk', MasteryState.emerging, prerequisites: ['pk']);
      final back = FeedbackConcept.fromJson(c.toJson());
      expect(back.prerequisites, ['pk']);
      final old = c.toJson()..remove('prerequisites');
      expect(FeedbackConcept.fromJson(old).prerequisites, isEmpty);
    });

    test('from a course concept and the engine estimate', () {
      const concept = Concept(
        id: 'fk',
        name: LocalizedText(ar: 'المفتاح الأجنبي', en: 'Foreign key'),
        prerequisites: ['pk'],
      );
      final c = FeedbackConcept.from(
        concept,
        const ConceptMastery(
          evidence: ConceptEvidence(conceptId: 'fk', attempts: 3, correct: 1),
          state: MasteryState.possibleDifficulty,
        ),
      );
      expect(c.state, MasteryState.possibleDifficulty);
      expect((c.correct, c.attempts), (1, 3));
      expect(c.prerequisites, ['pk']);
      final none = FeedbackConcept.from(concept, null);
      expect(none.state, MasteryState.insufficientEvidence);
      expect(none.attempts, 0);
    });
  });

  testWidgets('map in Arabic: levels, evidence, cautious hint', (
    tester,
  ) async {
    await _show(tester, const Locale('ar'));
    expect(find.text('خريطتك المعرفية لهذه الجلسة'), findsOneWidget);
    expect(find.text('الأساسيات'), findsOneWidget);
    expect(find.text('المستوى 3'), findsOneWidget);
    expect(find.text('صعوبة محتملة · أجبت صح على 0 من 2 أسئلة عنه'), findsNWidgets(2));
    expect(find.text('يعتمد على: مفهوم pk'), findsOneWidget);
    expect(
      find.text('قد يكون «مفهوم pk» سبباً محتملاً، تستحسن مراجعته أولاً.'),
      findsOneWidget,
    );
    // No attempts: the state only, no "0 of 0".
    expect(find.text('دليل غير كافٍ'), findsWidgets);
  });

  testWidgets('map in English fits a small phone with large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _show(tester, const Locale('en'), size: const Size(320, 2400));
    expect(find.text('Your knowledge map for this session'), findsOneWidget);
    expect(find.text('Builds on: Concept fk, Concept rel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save turns the map into a PNG on the device', (tester) async {
    Uint8List? saved;
    String? name;
    await _show(
      tester,
      const Locale('en'),
      save: (png, fileName) async {
        saved = png;
        name = fileName;
      },
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save the map to my phone'));
      // toImage and PNG encoding run outside the fake clock.
      for (var i = 0; i < 50 && saved == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    expect(name, 'bousla-knowledge-map.png');
    expect(saved, isNotNull);
    // PNG signature.
    expect(saved!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    expect(find.text('Map saved as an image.'), findsOneWidget);
  });

  testWidgets('a failed save says so and suggests a screenshot', (
    tester,
  ) async {
    await _show(
      tester,
      const Locale('en'),
      save: (_, __) async => throw Exception('blocked'),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Save the map to my phone'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump();
    expect(
      find.text('Could not save the image. Take a screenshot instead.'),
      findsOneWidget,
    );
  });
}
