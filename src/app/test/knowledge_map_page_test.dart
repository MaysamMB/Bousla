import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the feedback page links to the knowledge map on its own page',
      (tester) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    final session = await services.sessions.createSession(
      courseId: 'database_systems',
      ownerId: 'teacher',
      questions: const [],
    );
    await services.sessions.saveFeedback(session.id, {
      'me': const StudentFeedback(
        language: Language.en,
        concepts: [
          FeedbackConcept(
            conceptId: 'primary_key',
            name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
            state: MasteryState.emerging,
            attempts: 2,
            correct: 1,
          ),
          FeedbackConcept(
            conceptId: 'foreign_key',
            name: LocalizedText(ar: 'المفتاح الأجنبي', en: 'Foreign Key'),
            state: MasteryState.possibleDifficulty,
            attempts: 2,
            correct: 0,
            prerequisites: ['primary_key'],
          ),
        ],
      ),
    });
    await services.sessions.closeSession(session.id);
    await services.sessions.releaseFeedback(session.id);

    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: FeedbackScreen(sessionId: session.id, participantId: 'me'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The feedback page stays short: the map is behind a button.
    expect(find.text('Your knowledge map for this session'), findsNothing);
    await tester.ensureVisible(find.text('Show my knowledge map'));
    await tester.tap(find.text('Show my knowledge map'));
    await tester.pumpAndSettle();

    expect(find.text('Knowledge map'), findsOneWidget);
    expect(find.text('Your knowledge map for this session'), findsOneWidget);
    expect(find.text('Builds on: Primary Key'), findsOneWidget);
    expect(find.text('Save the map to my phone'), findsOneWidget);

    // Back returns to the feedback.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Show my knowledge map'), findsOneWidget);
  });
}
