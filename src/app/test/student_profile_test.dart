import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:bousla_app/data/repositories/profile_repository.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _me = 'participant'; // InMemoryAuthService's student

const _feedback = StudentFeedback(
  language: Language.en,
  concepts: [
    FeedbackConcept(
      conceptId: 'primary_key',
      name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
      state: MasteryState.emerging,
      attempts: 2,
      correct: 1,
    ),
  ],
);

/// Safari blocks the first sign-in window (not opened straight from a tap).
class _BlockedOnceAuth extends InMemoryAuthService {
  var tries = 0;

  @override
  Future<StudentAccount> linkStudentAccount() {
    tries++;
    if (tries == 1) {
      throw const StudentLinkFailure(StudentLinkProblem.popupBlocked);
    }
    return super.linkStudentAccount();
  }
}

/// The Google account already has a profile from another browser, and the
/// sign-in window to it is blocked the first time.
class _ExistingBlockedOnceAuth extends InMemoryAuthService {
  _ExistingBlockedOnceAuth() {
    existingStudentUid = 'elsewhere';
  }

  var switches = 0;

  @override
  Future<StudentAccount> switchToLinkedStudentAccount() {
    switches++;
    if (switches == 1) {
      throw const StudentLinkFailure(StudentLinkProblem.popupBlocked);
    }
    return super.switchToLinkedStudentAccount();
  }
}

/// The instructor dashboard was used in this browser: no anonymous student.
class _InstructorSignedInAuth extends InMemoryAuthService {
  @override
  Future<StudentAccount> linkStudentAccount() => throw const StudentLinkFailure(
      StudentLinkProblem.instructorSignedIn, 'not-anonymous');
}

Future<(AppServices, Session)> _setUp({AuthService? auth}) async {
  final services = auth == null
      ? AppServices.inMemory(initialLocale: const Locale('en'))
      : AppServices(
          content: InMemoryContentRepository(),
          sessions: InMemorySessionRepository(),
          auth: auth,
          inMemory: true,
          initialLocale: const Locale('en'),
        );
  final session = await services.sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: const [],
  );
  await services.sessions.closeSession(session.id);
  await services.sessions.saveFeedback(session.id, {_me: _feedback});
  await services.sessions.releaseFeedback(session.id);
  return (services, session);
}

/// Lets the in-memory repositories' real async work finish (pumpAndSettle
/// alone does not, while a spinner runs).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _show(WidgetTester tester, AppServices services, Session s) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(
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
      home: FeedbackScreen(sessionId: s.id, participantId: _me),
    ),
  ));
  await _settle(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('declining stores nothing; agreeing saves the session',
      (tester) async {
    final (services, session) = await _setUp();
    await _show(tester, services, session);
    expect(find.text('Keep your progress (optional)'), findsOneWidget);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsOneWidget);
    expect(find.textContaining('Who sees it: only you'), findsOneWidget);
    await tester.tap(find.text('No, thanks'));
    await tester.pumpAndSettle();
    expect(services.auth.studentAccount, isNull);
    expect(await services.profiles.consentVersion(_me), isNull);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('This session is in your profile.'), findsOneWidget);
    expect(services.auth.studentAccount, isNotNull);
    expect(await services.profiles.hasSession(_me, session.id), isTrue);
  });

  testWidgets(
      'a Google account with a profile from another browser: '
      'cancel keeps nothing, continue adds this session to it', (tester) async {
    final auth = InMemoryAuthService()..existingStudentUid = 'elsewhere';
    final (services, session) = await _setUp(auth: auth);
    await services.profiles.create('elsewhere');
    await _show(tester, services, session);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('existing-profile')), findsOneWidget);
    expect(find.text('You already have a Bousla profile'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(services.auth.studentAccount, isNull);
    expect(
        await services.profiles.hasSession('elsewhere', session.id), isFalse);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in and add the session'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('This session is in your profile.'), findsOneWidget);
    expect(services.auth.studentAccount?.uid, 'elsewhere');
    expect(await services.profiles.hasSession('elsewhere', session.id), isTrue);
    expect(await services.profiles.hasSession(_me, session.id), isFalse);
  });

  testWidgets(
      'the window to the existing profile is blocked: the next tap '
      'opens it, with no dialog in between', (tester) async {
    final auth = _ExistingBlockedOnceAuth();
    final (services, session) = await _setUp(auth: auth);
    await _show(tester, services, session);

    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in and add the session'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Continue signing in with Google'), findsOneWidget);

    await tester.tap(find.text('Continue signing in with Google'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsNothing);
    expect(find.byKey(const ValueKey('existing-profile')), findsNothing);
    expect(auth.switches, 2);
    // That profile had no consent record yet: created from this agreement.
    expect(await services.profiles.consentVersion('elsewhere'), 1);
    expect(await services.profiles.hasSession('elsewhere', session.id), isTrue);
  });

  testWidgets('my profile: progress, remove a session, delete everything',
      (tester) async {
    final (services, session) = await _setUp();
    await services.auth.linkStudentAccount();
    await services.profiles.create(_me);
    await services.profiles.saveSession(_me, session, _feedback);
    await _show(tester, services, session);
    expect(find.text('This session is in your profile.'), findsOneWidget);

    await tester.tap(find.text('Open my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('My profile'), findsOneWidget);
    expect(find.text('Primary Key'), findsOneWidget);
    expect(find.textContaining('Still forming'), findsOneWidget);
    expect(find.textContaining('1 of 2'), findsOneWidget);
    // Inside its own session, not in a list across sessions.
    expect(
      find.descendant(
        of: find.byKey(ValueKey('session-${session.id}')),
        matching: find.text('Primary Key'),
      ),
      findsOneWidget,
    );

    // A name and a preset picture, for the student only.
    expect(find.text('Add your name'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit name and picture'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('profile-name')), ' Sara ');
    await tester.tap(find.byKey(const ValueKey('avatar-3')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Sara'), findsOneWidget);
    final info = await services.profiles.info(_me);
    expect(info.displayName, 'Sara');
    expect(info.avatar, 3);
    // Agreeing again keeps the consent record separate from the name.
    expect(await services.profiles.consentVersion(_me), 1);

    await tester.tap(find.byTooltip('Remove from my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(await services.profiles.hasSession(_me, session.id), isFalse);
    expect(find.text('No sessions added yet.'), findsWidgets);

    await tester.tap(find.text('Delete my whole profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('without your name'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(await services.profiles.consentVersion(_me), isNull);
    expect((await services.profiles.info(_me)).displayName, isNull);
    expect(find.text('Your profile was deleted.'), findsOneWidget);
  });

  testWidgets('a blocked sign-in window: one more tap, no second consent',
      (tester) async {
    final auth = _BlockedOnceAuth();
    final (services, session) = await _setUp(auth: auth);
    await _show(tester, services, session);
    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Continue signing in with Google'), findsOneWidget);
    expect(await services.profiles.consentVersion(_me), isNull);

    await tester.tap(find.text('Continue signing in with Google'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-consent')), findsNothing);
    expect(find.text('This session is in your profile.'), findsOneWidget);
    expect(auth.tries, 2);
    expect(await services.profiles.hasSession(_me, session.id), isTrue);
  });

  testWidgets('an instructor signed in to this browser: a message that says so',
      (tester) async {
    final (services, session) = await _setUp(auth: _InstructorSignedInAuth());
    await _show(tester, services, session);
    await tester.tap(find.text('Add this session to my profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I agree, create my profile'));
    await _settle(tester);
    await tester.pump();
    expect(find.textContaining('signed in to an instructor account'),
        findsOneWidget);
    expect(find.text('Add this session to my profile'), findsOneWidget);
    expect(await services.profiles.hasSession(_me, session.id), isFalse);
  });

  test('a name is trimmed and cut; an unknown picture is dropped', () {
    final long = cleanProfileInfo(ProfileInfo(displayName: 'x' * 50));
    expect(long.displayName!.length, ProfileInfo.maxNameLength);
    final blank =
        cleanProfileInfo(const ProfileInfo(displayName: '  ', avatar: 12));
    expect(blank.displayName, isNull);
    expect(blank.avatar, isNull);
    expect(cleanProfileInfo(const ProfileInfo(avatar: 0)).avatar, 0);
  });
}
