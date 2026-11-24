import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/feedback_explainer.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:bousla_app/features/instructor/sessions/create_session_screen.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/features/student_web/join_session/join_screen.dart';
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
    testWidgets('English: state, evidence, hint, step, AI label, LTR',
        (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback());
      await tester.pumpWidget(_app(
        services,
        FeedbackScreen(sessionId: session.id, participantId: _me),
      ));
      await tester.pumpAndSettle();

      // The name is also in the knowledge map: check the concept list.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('Primary Key'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('May need review'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('You answered 1 of 3 correctly'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-foreign_key')),
          matching: find.text('Shown good understanding'),
        ),
        findsOneWidget,
      );
      expect(find.text('You answered 4 of 4 correctly'), findsOneWidget);
      expect(
        find.text('Reviewing Primary Key first may help with Foreign Key.'),
        findsOneWidget,
      );
      expect(find.text('Review Primary Key'), findsOneWidget);
      expect(find.text('Primary keys explained'), findsOneWidget);
      expect(find.text('https://example.com/pk'), findsOneWidget);
      expect(find.text('Primary Key may need review.'), findsOneWidget);
      expect(find.text('AI-generated'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(FeedbackView))),
        TextDirection.ltr,
      );
      // Order: concepts, hints, next steps, explanation.
      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(y('Concepts'), lessThan(y('Foundations that may help')));
      expect(y('Foundations that may help'), lessThan(y('Next steps')));
      expect(y('Next steps'), lessThan(y('About your results')));
    });

    testWidgets('Arabic: wording and RTL', (tester) async {
      _tallView(tester);
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback(language: Language.ar));
      await tester.pumpWidget(_app(
        services,
        FeedbackScreen(sessionId: session.id, participantId: _me),
        locale: 'ar',
      ));
      await tester.pumpAndSettle();

      // The name is also in the knowledge map: check the concept list.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('المفتاح الأساسي'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('قد يحتاج مراجعة'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-primary_key')),
          matching: find.text('أجبت 1 من 3 بشكل صحيح'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('concept-foreign_key')),
          matching: find.text('أظهرت فهمًا جيدًا'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('قد يساعدك مراجعة المفتاح الأساسي أولًا قبل المفتاح الخارجي.'),
        findsOneWidget,
      );
      expect(find.text('قد يحتاج المفتاح الأساسي إلى مراجعة.'), findsOneWidget);
      expect(find.text('مولّد بالذكاء الاصطناعي'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(FeedbackView))),
        TextDirection.rtl,
      );
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
        FeedbackScreen(sessionId: session.id, participantId: _me),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Primary Key may need review.'), findsOneWidget);
      expect(find.text('AI-generated'), findsNothing);
      expect(find.byKey(const ValueKey('ai-label')), findsNothing);
    });

    testWidgets('opens in the language of the feedback', (tester) async {
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
            home: FeedbackScreen(sessionId: session.id, participantId: _me),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(services.locale.value.languageCode, 'en');
      expect(find.text('May need review'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('the thank-you screen opens feedback once it is published',
        (tester) async {
      final (services, sessions, session) = await _setUp();
      await tester.pumpWidget(_app(
        services,
        AnsweringScreen(session: session, participantId: _me),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Thank you! Your answers were submitted.'),
          findsOneWidget);
      expect(find.byType(FeedbackScreen), findsNothing);

      await sessions.closeSession(session.id);
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsNothing,
          reason: 'closed, not yet published');

      await sessions.saveFeedback(session.id, {_me: _feedback()});
      await sessions.releaseFeedback(session.id);
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(find.text('May need review'), findsOneWidget);
    });

    testWidgets('reopening a closed session link shows published feedback',
        (tester) async {
      final (services, sessions, session) = await _setUp();
      await _publish(sessions, session, _feedback());
      await tester.pumpWidget(_app(
        services,
        JoinScreen(initialCode: session.code),
      ));
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsOneWidget);
      expect(find.text('You answered 1 of 3 correctly'), findsOneWidget);
    });

    testWidgets('closed without published feedback: still "session closed"',
        (tester) async {
      final (services, sessions, session) = await _setUp();
      await sessions.closeSession(session.id);
      // Saved but not released: students must not see it.
      await sessions.saveFeedback(session.id, {_me: _feedback()});
      await tester.pumpWidget(_app(
        services,
        JoinScreen(initialCode: session.code),
      ));
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsNothing);
      expect(find.text('This session is closed.'), findsOneWidget);
    });

    testWidgets('released, but nothing for this browser: says where to look',
        (tester) async {
      final (services, sessions, session) = await _setUp();
      await sessions.closeSession(session.id);
      await sessions.saveFeedback(session.id, {'someone-else': _feedback()});
      await sessions.releaseFeedback(session.id);
      await tester.pumpWidget(_app(
        services,
        JoinScreen(initialCode: session.code),
      ));
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedbackScreen), findsNothing);
      expect(
        find.textContaining('There is no feedback for you in this session'),
        findsOneWidget,
      );
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
      tester.view.physicalSize = const Size(1200, 2400);
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
      // Tall enough for the live insights panel above the buttons.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
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
