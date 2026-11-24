import 'dart:async';

import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/feedback_explainer.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:bousla_app/features/instructor/sessions/create_session_screen.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/features/student_web/feedback/my_feedback_screen.dart';
import 'package:bousla_app/features/student_web/knowledge_map/knowledge_map_view.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The participant ID of "this browser" ([InMemoryAuthService]).
const _me = 'participant';

StudentFeedback _feedback({
  ExplanationSource source = ExplanationSource.ai,
  Language language = Language.en,
}) =>
    StudentFeedback(
      language: language,
      concepts: const [
        FeedbackConcept(
          conceptId: 'primary_key',
          name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
          state: MasteryState.possibleDifficulty,
          attempts: 3,
          correct: 1,
        ),
        FeedbackConcept(
          conceptId: 'foreign_key',
          name: LocalizedText(ar: 'المفتاح الخارجي', en: 'Foreign Key'),
          state: MasteryState.demonstratedMastery,
          attempts: 4,
          correct: 4,
        ),
      ],
      hints: const [
        FeedbackHint(
          conceptId: 'foreign_key',
          prerequisiteId: 'primary_key',
          signal: PrerequisiteSignal.possibleContributingGap,
        ),
      ],
      recommendations: const [
        FeedbackRecommendation(
          conceptId: 'primary_key',
          reason: RecommendationReason.reviewConcept,
          resources: [
            FeedbackResource(
              id: 'res_pk_video',
              title: LocalizedText(ar: 'شرح المفتاح الأساسي', en: 'Primary keys explained'),
              type: ResourceType.video,
              url: 'https://example.com/pk',
            ),
          ],
        ),
      ],
      explanation: FeedbackExplanation(
        text: const LocalizedText(
          ar: 'قد يحتاج المفتاح الأساسي إلى مراجعة.',
          en: 'Primary Key may need review.',
        ),
        source: source,
        model: source == ExplanationSource.ai ? 'fake-gemini' : null,
      ),
    );

Widget _app(AppServices services, Widget home, {String locale = 'en'}) =>
    ServicesScope(
      services: services,
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

/// A session with one approved question that [_me] answered.
Future<(AppServices, InMemorySessionRepository, Session)> _setUp({
  FeedbackExplainer? explainer,
}) async {
  final content = InMemoryContentRepository();
  final sessions = InMemorySessionRepository();
  final services = AppServices(
    content: content,
    sessions: sessions,
    feedbackExplainer: explainer,
  );
  final q = (await content.listQuestions('database_systems')).first;
  final session = await sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [QuestionRef(q.id, q.version)],
  );
  await sessions.submitResponse(
    session.id,
    Response(
      participantId: _me,
      questionId: q.id,
      questionVersion: q.version,
      selectedOptionId: q.options.first.id,
      displayLanguage: Language.en,
    ),
  );
  return (services, sessions, session);
}

Future<void> _publish(
  InMemorySessionRepository sessions,
  Session session,
  StudentFeedback feedback,
) async {
  await sessions.closeSession(session.id);
  await sessions.saveFeedback(session.id, {_me: feedback});
  await sessions.releaseFeedback(session.id);
}

/// Publishing awaits in-memory stream cancellations that complete on the
/// real event loop, which the widget test's fake clock does not run.
Future<void> _finishPublishing(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Tall enough that the whole feedback list is built.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4800);
  addTearDown(tester.view.reset);
}

void main() {
  group('feedback screen', () {
    testWidgets('English: explanation, AI label, next steps, map, LTR',
        (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback());
      await tester.pumpWidget(_app(
        services,
        MyFeedbackScreen(session: session, participantId: _me),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Primary Key may need review.'), findsOneWidget);
      expect(find.text('AI-generated'), findsOneWidget);
      expect(find.text('Review Primary Key'), findsOneWidget);
      expect(find.text('Primary keys explained'), findsOneWidget);
      expect(find.text('https://example.com/pk'), findsOneWidget);
      // The map: every state with its evidence.
      expect(find.text('May need review · You answered 1 of 3 correctly'),
          findsOneWidget);
      expect(
          find.text('Shown good understanding · You answered 4 of 4 correctly'),
          findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(FeedbackSummary))),
        TextDirection.ltr,
      );
      // Order: explanation, next steps, then the map.
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(find.text('About your results')),
          lessThan(y(find.text('Next steps'))));
      expect(y(find.text('Next steps')),
          lessThan(y(find.byType(KnowledgeMapView))));
    });

    testWidgets('Arabic: wording, evidence and RTL', (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback(language: Language.ar));
      await tester.pumpWidget(_app(
        services,
        MyFeedbackScreen(session: session, participantId: _me),
        locale: 'ar',
      ));
      await tester.pumpAndSettle();

      expect(find.text('قد يحتاج المفتاح الأساسي إلى مراجعة.'), findsOneWidget);
      expect(find.text('مولّد بالذكاء الاصطناعي'), findsOneWidget);
      expect(find.text('راجع المفتاح الأساسي'), findsOneWidget);
      expect(find.text('شرح المفتاح الأساسي'), findsOneWidget);
      expect(find.text('قد يحتاج مراجعة · أجبت 1 من 3 بشكل صحيح'),
          findsOneWidget);
      expect(find.text('أظهرت فهمًا جيدًا · أجبت 4 من 4 بشكل صحيح'),
          findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(FeedbackSummary))),
        TextDirection.rtl,
      );
    });

    testWidgets('feedback stays on screen when nothing changes for minutes',
        (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback());
      await tester.pumpWidget(_app(
        services,
        MyFeedbackScreen(session: session, participantId: _me),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Primary Key may need review.'), findsOneWidget);
      // Longer than the first-answer limit (20 s) with no new event.
      await tester.pump(const Duration(seconds: 25));
      await tester.pump(const Duration(minutes: 2));
      expect(find.text('Primary Key may need review.'), findsOneWidget);
      expect(find.textContaining('connection is slow'), findsNothing);
    });

    test('only a missing FIRST event is a timeout', () async {
      final quiet = StreamController<int>();
      final events = <Object>[];
      final sub = firstEventWithin(quiet.stream, const Duration(milliseconds: 50))
          .listen(events.add, onError: events.add);
      quiet.add(1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(events, [1]);
      await sub.cancel();

      final silent = StreamController<int>();
      final errors = <Object>[];
      final sub2 =
          firstEventWithin(silent.stream, const Duration(milliseconds: 50))
              .listen((_) {}, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(errors.first, isA<TimeoutException>());
      await sub2.cancel();
    });

    testWidgets('no AI label for a template explanation', (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(
        sessions,
        session,
        _feedback(source: ExplanationSource.template),
      );
      await tester.pumpWidget(_app(
        services,
        MyFeedbackScreen(session: session, participantId: _me),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Primary Key may need review.'), findsOneWidget);
      expect(find.text('AI-generated'), findsNothing);
      expect(find.byKey(const ValueKey('ai-label')), findsNothing);
    });

    testWidgets('opens in the language of the feedback', (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback(language: Language.en));
      expect(services.locale.value.languageCode, 'ar');
      await tester.pumpWidget(ServicesScope(
        services: services,
        child: ValueListenableBuilder<Locale>(
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
            home: MyFeedbackScreen(session: session, participantId: _me),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(services.locale.value.languageCode, 'en');
      expect(find.text('Review Primary Key'), findsOneWidget);
    });

    testWidgets("another participant's feedback is not shown", (tester) async {
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback());
      await tester.pumpWidget(_app(
        services,
        MyFeedbackScreen(session: session, participantId: 'someone-else'),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('There is no feedback for you'),
          findsOneWidget);
      expect(find.text('Primary Key may need review.'), findsNothing);
    });

    testWidgets('reopening the screen shows the saved text, no model call',
        (tester) async {
      _tallView(tester);
      final explainer = _CountingExplainer();
      final (services, sessions, session) = await _setUp(explainer: explainer);
      await _publish(sessions, session, _feedback());
      for (var i = 0; i < 2; i++) {
        // A fresh screen each time, as after a page reload.
        await tester.pumpWidget(_app(
          services,
          MyFeedbackScreen(
            key: ValueKey(i),
            session: session,
            participantId: _me,
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('Primary Key may need review.'), findsOneWidget);
      }
      expect(explainer.calls, 0);
    });
  });

  group('summary', () {
    StudentFeedback withExtras() {
      final f = _feedback();
      return StudentFeedback(
        language: f.language,
        concepts: f.concepts,
        hints: const [
          FeedbackHint(
            conceptId: 'foreign_key',
            prerequisiteId: 'primary_key',
            signal: PrerequisiteSignal.needsMoreEvidence,
          ),
        ],
        recommendations: const [
          FeedbackRecommendation(
            conceptId: 'primary_key',
            reason: RecommendationReason.reviewConcept,
            resources: [
              FeedbackResource(
                id: 'res_pk_video',
                title: LocalizedText(ar: 'فيديو', en: 'Primary keys explained'),
                type: ResourceType.video,
                url: 'https://example.com/pk',
              ),
              FeedbackResource(
                id: 'res_bad',
                title: LocalizedText(ar: 'سيء', en: 'Not a web link'),
                type: ResourceType.link,
                url: 'javascript:alert(1)',
              ),
            ],
          ),
        ],
        explanation: f.explanation,
      );
    }

    testWidgets('a prerequisite without enough evidence is worded cautiously',
        (tester) async {
      final (services, _, _) = await _setUp();
      await tester.pumpWidget(_app(
        services,
        Scaffold(body: ListView(children: [FeedbackSummary(feedback: withExtras())])),
      ));
      await tester.pumpAndSettle();
      expect(
        find.text('There is not enough evidence yet about Primary Key, '
            'which Foreign Key builds on.'),
        findsOneWidget,
      );
      expect(find.text('These are possibilities, not a diagnosis.'),
          findsOneWidget);
    });

    testWidgets('a resource opens its stored web link only', (tester) async {
      final (services, _, _) = await _setUp();
      final opened = <Uri>[];
      await tester.pumpWidget(_app(
        services,
        Scaffold(
          body: ListView(children: [
            FeedbackSummary(
              feedback: withExtras(),
              openLink: (url) async => opened.add(url),
            ),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Primary keys explained'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://example.com/pk')]);
      // Not a web link: shown as an activity, not opened.
      await tester.tap(find.text('Not a web link'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(find.textContaining('javascript'), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets('the thank-you screen opens feedback once it is released',
        (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await tester.pumpWidget(_app(
        services,
        AnsweringScreen(session: session, participantId: _me),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Thank you! Your answers were submitted.'),
          findsOneWidget);
      expect(find.byType(MyFeedbackScreen), findsNothing);

      await sessions.closeSession(session.id);
      await sessions.saveFeedback(session.id, {_me: _feedback()});
      await tester.pumpAndSettle();
      expect(find.byType(MyFeedbackScreen), findsNothing,
          reason: 'saved but not released yet');

      await sessions.releaseFeedback(session.id);
      await tester.pumpAndSettle();
      expect(find.byType(MyFeedbackScreen), findsOneWidget);
      expect(find.text('Primary Key may need review.'), findsOneWidget);
    });
  });

  group('instructor', () {
    Future<void> closeAndOpenDialog(WidgetTester tester) async {
      await tester.tap(find.text('Create session'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Close session'));
      await tester.tap(find.text('Close session'));
      await tester.pumpAndSettle();
      expect(find.text('Session closed'), findsOneWidget);
      await tester.ensureVisible(find.text('Publish feedback'));
      await tester.tap(find.text('Publish feedback'));
      await tester.pumpAndSettle();
    }

    testWidgets('publishes after closing; AI off when not available',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      addTearDown(tester.view.reset);
      final services = AppServices.inMemory(initialLocale: const Locale('en'));
      await tester.pumpWidget(_app(services, const CreateSessionScreen()));
      await tester.pumpAndSettle();
      await closeAndOpenDialog(tester);

      expect(find.text('Add an AI explanation'), findsOneWidget);
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged, isNull);
      expect(toggle.value, isFalse);

      await tester.tap(find.text('Publish'));
      await _finishPublishing(tester);
      expect(find.text('Feedback published for 0 students.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.text(
            'Feedback published. Students can open it from the session link.'),
        findsOneWidget,
      );
      expect(find.text('Publish feedback'), findsNothing);
    });

    testWidgets('the AI option can be switched off', (tester) async {
      tester.view.physicalSize = const Size(1200, 6000);
      addTearDown(tester.view.reset);
      final explainer = _CountingExplainer();
      final services = AppServices(
        content: InMemoryContentRepository(),
        sessions: InMemorySessionRepository(),
        auth: InMemoryAuthService(),
        feedbackExplainer: explainer,
        initialLocale: const Locale('en'),
      );
      await tester.pumpWidget(_app(services, const CreateSessionScreen()));
      await tester.pumpAndSettle();
      // One student answers, so there is something to explain.
      final sessionId = 'session_1';
      await tester.tap(find.text('Create session'));
      await tester.pumpAndSettle();
      final q = (await services.content.listQuestions('database_systems'))
          .first;
      await services.sessions.submitResponse(
        sessionId,
        Response(
          participantId: 'p1',
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId: q.options.first.id,
          displayLanguage: Language.ar,
        ),
      );
      await tester.ensureVisible(find.text('Close session'));
      await tester.tap(find.text('Close session'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Publish feedback'));
      await tester.tap(find.text('Publish feedback'));
      await tester.pumpAndSettle();

      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(find.text('Publish'));
      await _finishPublishing(tester);
      expect(explainer.calls, 0);
      expect(find.text('Feedback published for 1 students.'), findsOneWidget);
      final f = await services.sessions.watchMyFeedback(sessionId, 'p1').first;
      expect(f!.explanation!.source, ExplanationSource.template);
    });
  });
}

class _CountingExplainer implements FeedbackExplainer {
  var calls = 0;

  @override
  Future<ExplainerAnswer> explain(List<ExplanationProfile> profiles) async {
    calls++;
    return const ExplainerAnswer(text: '[]', model: 'fake-gemini');
  }
}
