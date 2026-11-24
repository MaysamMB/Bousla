import 'dart:async';

import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers never reach the server: the request hangs.
class _HangingSessions extends InMemorySessionRepository {
  @override
  Future<void> submitResponse(String sessionId, Response response) =>
      Completer<void>().future;
}

Future<void> _show(
  WidgetTester tester,
  AppServices services,
  Session session,
  String participantId,
) async {
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
        home: AnsweringScreen(
          key: ValueKey(participantId),
          session: session,
          participantId: participantId,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<(AppServices, Session)> _setUp(
    InMemorySessionRepository sessions) async {
  final content = InMemoryContentRepository();
  final services = AppServices(content: content, sessions: sessions);
  final questions = await content.listQuestions('database_systems');
  final session = await sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  return (services, session);
}

void main() {
  testWidgets('after a reload the student continues at the first open question',
      (
    tester,
  ) async {
    final (services, session) = await _setUp(InMemorySessionRepository());
    final total = session.questions.length;
    expect(total, greaterThanOrEqualTo(3));
    // Two answers were saved before the page was reloaded.
    for (final ref in session.questions.take(2)) {
      await services.sessions.submitResponse(
        session.id,
        Response(
          participantId: 'p1',
          questionId: ref.questionId,
          questionVersion: ref.version,
          selectedOptionId: 'a',
          displayLanguage: Language.ar,
        ),
      );
    }
    await _show(tester, services, session, 'p1');
    expect(find.text('Question 3 of $total'), findsOneWidget);

    // Another student on the same session still starts at the beginning.
    await _show(tester, services, session, 'p2');
    expect(find.text('Question 1 of $total'), findsOneWidget);
  });

  testWidgets('a student who answered everything sees the thank-you page', (
    tester,
  ) async {
    final (services, session) = await _setUp(InMemorySessionRepository());
    for (final ref in session.questions) {
      await services.sessions.submitResponse(
        session.id,
        Response(
          participantId: 'p1',
          questionId: ref.questionId,
          questionVersion: ref.version,
          selectedOptionId: 'a',
          displayLanguage: Language.en,
        ),
      );
    }
    await _show(tester, services, session, 'p1');
    expect(
        find.text('Thank you! Your answers were submitted.'), findsOneWidget);
  });

  testWidgets('a hanging request shows a message instead of freezing', (
    tester,
  ) async {
    final (services, session) = await _setUp(_HangingSessions());
    await _show(tester, services, session, 'p1');
    await tester.tap(find.byType(ListTile).first);
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump(AnsweringScreen.timeout + const Duration(seconds: 1));
    expect(find.textContaining('The connection is slow'), findsOneWidget);
    // The student can press again.
    final submit = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(submit.onPressed, isNotNull);
  });
}
