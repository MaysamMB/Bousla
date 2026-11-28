// "I've reviewed this concept" ticks and the "Test My Understanding Again"
// button on the student's feedback page. The ticks are the student's own
// note, kept in this browser only: they never change the feedback and are
// never sent anywhere. (The follow-up itself: test/follow_up_test.dart.)
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_follow_up_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/session_repository.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/features/student_web/feedback/review_marks_store.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'participant';

/// Lets the screen read its feedback and records every other call: the
/// ticks must cause none.
class _RecordingSessions implements SessionRepository {
  _RecordingSessions(this._inner);

  final InMemorySessionRepository _inner;
  final calls = <Symbol>[];

  @override
  Stream<StudentFeedback?> watchMyFeedback(
          String sessionId, String participantId) =>
      _inner.watchMyFeedback(sessionId, participantId);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

/// A browser's localStorage, as a map.
class _FakeStorage {
  final values = <String, String>{};
  ReviewMarksStore store() => ReviewMarksStore(
        read: (k) => values[k],
        write: (k, v) => values[k] = v,
      );
}

FeedbackConcept _concept(
        String id, String ar, String en, MasteryState state, int a, int c) =>
    FeedbackConcept(
      conceptId: id,
      name: LocalizedText(ar: ar, en: en),
      state: state,
      attempts: a,
      correct: c,
    );

final _feedback = StudentFeedback(
  language: Language.en,
  concepts: [
    _concept('primary_key', 'المفتاح الأساسي', 'Primary Key',
        MasteryState.possibleDifficulty, 3, 1),
    _concept('sql_join', 'الربط', 'Joins', MasteryState.emerging, 3, 2),
    // Still forming, with no next step: its tick goes on its own card.
    _concept('er_modeling', 'نمذجة الكيانات', 'ER Modeling',
        MasteryState.emerging, 2, 1),
    _concept('foreign_key', 'المفتاح الخارجي', 'Foreign Key',
        MasteryState.demonstratedMastery, 4, 4),
    _concept('normalization', 'التطبيع', 'Normalization',
        MasteryState.insufficientEvidence, 1, 1),
  ],
  hints: const [],
  recommendations: const [
    FeedbackRecommendation(
      conceptId: 'primary_key',
      reason: RecommendationReason.reviewConcept,
      resources: [
        FeedbackResource(
          id: 'res_pk_video',
          title: LocalizedText(
              ar: 'شرح المفتاح الأساسي', en: 'Primary keys explained'),
          type: ResourceType.video,
          url: 'https://example.com/pk',
        ),
      ],
    ),
    FeedbackRecommendation(
      conceptId: 'sql_join',
      reason: RecommendationReason.practice,
      resources: [
        FeedbackResource(
          id: 'res_join',
          title: LocalizedText(ar: 'تمارين الربط', en: 'Join exercises'),
          type: ResourceType.activity,
        ),
      ],
    ),
    FeedbackRecommendation(
      conceptId: 'normalization',
      reason: RecommendationReason.assessMore,
      resources: [],
    ),
  ],
  explanation: null,
);

/// A released session where [_me] has [_feedback].
Future<(AppServices, _RecordingSessions, Session)> _setUp(
    {Language language = Language.en}) async {
  final content = InMemoryContentRepository();
  final inner = InMemorySessionRepository();
  final q = (await content.listQuestions('database_systems')).first;
  final session = await inner.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [QuestionRef(q.id, q.version)],
  );
  await inner.submitResponse(
    session.id,
    Response(
      participantId: _me,
      questionId: q.id,
      questionVersion: q.version,
      selectedOptionId: q.options.first.id,
      displayLanguage: language,
    ),
  );
  await inner.closeSession(session.id);
  await inner.saveFeedback(session.id, {
    _me: StudentFeedback(
      language: language,
      concepts: _feedback.concepts,
      hints: _feedback.hints,
      recommendations: _feedback.recommendations,
      explanation: null,
    ),
  });
  await inner.releaseFeedback(session.id);
  final recording = _RecordingSessions(inner);
  final services = AppServices(
    content: content,
    sessions: recording,
    followUps: InMemoryFollowUpRepository(
      content: content,
      sessions: inner,
      currentUser: () async => _me,
    ),
    initialLocale: Locale(language.name),
  );
  return (services, recording, session);
}

Future<void> _show(
  WidgetTester tester,
  AppServices services,
  Session session,
  ReviewMarksStore store, {
  String participantId = _me,
}) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KeyedSubtree(
    // A fresh page each time, as after a reload.
    key: UniqueKey(),
    child: ServicesScope(
      services: services,
      child: ValueListenableBuilder(
        valueListenable: services.locale,
        builder: (context, locale, _) => MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: FeedbackScreen(
            sessionId: session.id,
            participantId: participantId,
            reviewStore: store,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

final _ready = find.byKey(const ValueKey('follow-up-start'));
Finder _tick(String id) => find.byKey(ValueKey('reviewed-$id'));

bool _enabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(_ready).onPressed != null;

bool _ticked(WidgetTester tester, String id) =>
    tester.widget<CheckboxListTile>(_tick(id)).value ?? false;

/// What each concept card says (name, state, evidence).
List<String> _conceptTexts(WidgetTester tester) => [
      for (final c in _feedback.concepts)
        for (final e in find
            .descendant(
              of: find.byKey(ValueKey('concept-${c.conceptId}')),
              matching: find.byType(Text),
            )
            .evaluate())
          (e.widget as Text).data ?? '',
    ];

void main() {
  testWidgets('English: ticks only for "may need review" and "still forming"',
      (tester) async {
    final (services, _, session) = await _setUp();
    await _show(tester, services, session, _FakeStorage().store());

    expect(_tick('primary_key'), findsOneWidget);
    expect(_tick('sql_join'), findsOneWidget);
    expect(_tick('er_modeling'), findsOneWidget);
    expect(_tick('foreign_key'), findsNothing);
    expect(_tick('normalization'), findsNothing);
    expect(find.text("I've reviewed this concept"), findsNWidgets(3));

    // Under the concept's own resources, or on its card when it has none.
    final pkStep = find.ancestor(
        of: find.text('Primary keys explained'), matching: find.byType(Card));
    expect(find.descendant(of: pkStep, matching: _tick('primary_key')),
        findsOneWidget);
    expect(tester.getTopLeft(_tick('primary_key')).dy,
        greaterThan(tester.getTopLeft(find.text('Primary keys explained')).dy));
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('concept-er_modeling')),
            matching: _tick('er_modeling')),
        findsOneWidget);

    expect(find.text('Test My Understanding Again'), findsOneWidget);
    expect(Directionality.of(tester.element(_ready)), TextDirection.ltr);
  });

  testWidgets(
      'the button is off until one concept is ticked, and again off '
      'when every tick is removed', (tester) async {
    final (services, _, session) = await _setUp();
    await _show(tester, services, session, _FakeStorage().store());
    expect(_enabled(tester), isFalse);

    await tester.tap(_tick('sql_join'));
    await tester.pump();
    expect(_enabled(tester), isTrue);

    await tester.tap(_tick('sql_join'));
    await tester.pump();
    expect(_enabled(tester), isFalse);
  });

  testWidgets('each concept keeps its own tick', (tester) async {
    final (services, _, session) = await _setUp();
    await _show(tester, services, session, _FakeStorage().store());
    await tester.tap(_tick('primary_key'));
    await tester.pump();
    expect(_ticked(tester, 'primary_key'), isTrue);
    expect(_ticked(tester, 'sql_join'), isFalse);
    expect(_ticked(tester, 'er_modeling'), isFalse);
    await tester.tap(_tick('er_modeling'));
    await tester.pump();
    expect(_ticked(tester, 'primary_key'), isTrue);
    expect(_ticked(tester, 'sql_join'), isFalse);
    expect(_ticked(tester, 'er_modeling'), isTrue);
  });

  testWidgets('a tick changes no state, evidence or step, and sends nothing',
      (tester) async {
    final (services, recording, session) = await _setUp();
    await _show(tester, services, session, _FakeStorage().store());
    final before = _conceptTexts(tester);
    expect(before,
        containsAll(['May need review', 'You answered 1 of 3 correctly']));

    await tester.tap(_tick('primary_key'));
    await tester.tap(_tick('sql_join'));
    await tester.pump();

    expect(_conceptTexts(tester), before);
    expect(find.text('Review Primary Key'), findsOneWidget);
    // The feedback stored for the student is untouched.
    final stored =
        await recording._inner.watchMyFeedback(session.id, _me).first;
    expect(
        stored!.concepts
            .map((c) => (c.conceptId, c.state, c.correct, c.attempts)),
        _feedback.concepts
            .map((c) => (c.conceptId, c.state, c.correct, c.attempts)));
    // Only reads: no write of any kind to the session repository, and no
    // follow-up is made by ticking.
    expect(recording.calls, isEmpty);
    expect(
        (services.followUps! as InMemoryFollowUpRepository).storedAttempts,
        isEmpty);
  });

  testWidgets(
      'ticks come back after a reload; other sessions and students '
      'are kept apart', (tester) async {
    final (services, _, session) = await _setUp();
    final storage = _FakeStorage();
    await _show(tester, services, session, storage.store());
    await tester.tap(_tick('primary_key'));
    await tester.pump();
    expect(storage.values.keys, [ReviewMarksStore.keyFor(session.id, _me)]);

    // Reload: a new page, the same browser storage.
    await _show(tester, services, session, storage.store());
    expect(_ticked(tester, 'primary_key'), isTrue);
    expect(_ticked(tester, 'sql_join'), isFalse);
    expect(_enabled(tester), isTrue);

    // Another session in the same browser starts with no ticks.
    final store = storage.store();
    expect(store.load('another-session', _me), isEmpty);
    expect(store.load(session.id, 'another-student'), isEmpty);
  });

  test('missing, malformed or unavailable storage gives no ticks', () {
    final storage = _FakeStorage();
    final store = storage.store();
    expect(store.load('s', 'p'), isEmpty);
    for (final bad in ['not json', '{"a":1}', '42', '[1, null, ""]']) {
      storage.values[ReviewMarksStore.keyFor('s', 'p')] = bad;
      expect(store.load('s', 'p'), isEmpty, reason: bad);
    }
    storage.values[ReviewMarksStore.keyFor('s', 'p')] = '["a", 3, "b"]';
    expect(store.load('s', 'p'), {'a', 'b'});

    final blocked = ReviewMarksStore(
      read: (_) => throw StateError('blocked'),
      write: (_, __) => throw StateError('blocked'),
    );
    expect(blocked.load('s', 'p'), isEmpty);
    blocked.save('s', 'p', {'a'}); // No error.
  });

  testWidgets('Arabic: texts in Arabic, right to left', (tester) async {
    final (services, _, session) = await _setUp(language: Language.ar);
    await _show(tester, services, session, _FakeStorage().store());
    expect(find.text('راجعتُ هذا المفهوم'), findsNWidgets(3));
    expect(find.text('اختبر فهمي مرة أخرى'), findsOneWidget);
    expect(Directionality.of(tester.element(_ready)), TextDirection.rtl);
    expect(Directionality.of(tester.element(_tick('primary_key'))),
        TextDirection.rtl);
  });

  testWidgets('where feedback is only shown, there are no ticks',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: FeedbackView(feedback: _feedback)),
    ));
    await tester.pumpAndSettle();
    expect(find.text("I've reviewed this concept"), findsNothing);
    expect(_ready, findsNothing);
  });
}
