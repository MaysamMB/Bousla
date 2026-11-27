// Fixes from the 27 Nov team rehearsal:
// - a reload brings the student back with the session code filled in;
// - closing the session while a student answers tells them at once;
// - "Other" as a reject reason lets the instructor write it;
// - the instructor can share the session's code and link;
// - the career path offers "another job" (front end only).
import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/profile_repository.dart';
import 'package:bousla_app/features/instructor/sessions/share_feedback.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/features/student_web/career/career_screen.dart';
import 'package:bousla_app/features/student_web/join_session/join_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(AppServices services, Widget home) => ServicesScope(
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
        home: home,
      ),
    );

AppServices _services() => AppServices.inMemory(initialLocale: const Locale('en'));

void main() {
  testWidgets('after a reload the remembered code is filled in; a link code '
      'wins', (tester) async {
    await tester.pumpWidget(
        _app(_services(), JoinScreen(rememberedCode: () => 'ABC234')));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'ABC234'), findsOneWidget);

    await tester.pumpWidget(_app(
        _services(),
        JoinScreen(
          key: const ValueKey('link'),
          initialCode: 'XYZ789',
          rememberedCode: () => 'ABC234',
        )));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'XYZ789'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'ABC234'), findsNothing);
  });

  testWidgets('closing the session mid-way tells the student at once',
      (tester) async {
    final content = InMemoryContentRepository();
    final sessions = InMemorySessionRepository();
    final services = AppServices(content: content, sessions: sessions);
    final questions = await content.listQuestions('database_systems');
    final session = await sessions.createSession(
      courseId: 'database_systems',
      ownerId: 'teacher',
      questions: [for (final q in questions) QuestionRef(q.id, q.version)],
    );
    await tester.pumpWidget(_app(
        services, AnsweringScreen(session: session, participantId: 'p1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Question 1'), findsOneWidget);

    await tester.runAsync(() => sessions.closeSession(session.id));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('closed-early')), findsOneWidget);
    expect(find.textContaining('Your answers so far are kept'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('"Other" as a reject reason keeps what the instructor wrote',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = _services();
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review questions'));
    await tester.pumpAndSettle();

    final reject = find.text('Reject').first;
    await tester.ensureVisible(reject);
    await tester.pumpAndSettle();
    await tester.tap(reject);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reject-other')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('reject-other-note')), 'Not taught yet');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final all = await tester.runAsync(() => services.content
        .listQuestions('database_systems', approvedOnly: false));
    final rejected =
        all!.singleWhere((q) => q.status == ReviewStatus.rejected);
    expect(rejected.rejectionReason, RejectionReason.other);
    expect(rejected.rejectionNote, 'Not taught yet');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('the join message has the code and link in both languages', () {
    final session = Session(
      id: 's1',
      code: 'ABC234',
      courseId: 'c',
      ownerId: 't',
      questions: const [],
      status: SessionStatus.open,
      feedbackReleased: false,
      title: const LocalizedText(ar: 'المفاتيح', en: 'Keys'),
    );
    final m = shareJoinMessage(session, link: 'https://x/#/join/ABC234');
    expect(m, contains('«المفاتيح»'));
    expect(m, contains('«Keys»'));
    expect('ABC234'.allMatches(m).length, greaterThanOrEqualTo(2));
    expect(m, contains('https://x/#/join/ABC234'));
  });

  testWidgets('the share button opens the join message', (tester) async {
    final session = Session(
      id: 's1',
      code: 'ABC234',
      courseId: 'c',
      ownerId: 't',
      questions: const [],
      status: SessionStatus.open,
      feedbackReleased: false,
    );
    await tester.pumpWidget(_app(
        _services(), Scaffold(body: Center(child: ShareJoinButton(session: session)))));
    await tester.tap(find.byKey(const ValueKey('share-join')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Join code: ABC234'), findsOneWidget);
  });

  testWidgets('career path: "another job" says there is no data, saves nothing',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final role = careerRoleFromJson({
      'id': 'r',
      'title': {'ar': 'وظيفة', 'en': 'A job'},
      'source': {'kind': 'team_draft', 'name': 'Team draft'},
      'skills': [
        {'id': 's', 'name': {'ar': 's', 'en': 's'}, 'essential': true},
      ],
    });
    final sessions = [
      const SavedSession(code: 'S1', courseId: 'database_systems', concepts: []),
    ];
    await tester.pumpWidget(
        _app(_services(), CareerScreen(sessions: sessions, roles: [role])));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const ValueKey('role-other')));
    await tester.pump();
    await tester.enterText(
        find.byKey(const ValueKey('other-role-field')), 'Mobile developer');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('other-role-go')));
    await tester.pump();
    expect(find.byKey(const ValueKey('other-role-none')), findsOneWidget);
    expect(find.textContaining('“Mobile developer”'), findsOneWidget);

    // Back to a job with data.
    await tester.tap(find.byKey(const ValueKey('role-r')));
    await tester.pump();
    expect(find.byKey(const ValueKey('other-role-none')), findsNothing);
  });
}
