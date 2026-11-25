import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Requires sign-in and fails with a chosen problem.
class _FailingAuth implements AuthService {
  @override
  StudentAccount? get studentAccount => null;

  @override
  Future<StudentAccount> linkStudentAccount() =>
      throw const StudentLinkFailure(StudentLinkProblem.unknown);

  _FailingAuth(this.problem);

  final AuthProblem problem;
  var registerCalls = 0;

  @override
  bool get requiresSignIn => true;
  @override
  String? get instructorId => null;
  @override
  Stream<String?> instructorChanges() => Stream.value(null);
  @override
  Future<void> signInInstructor(String email, String password) async =>
      throw AuthFailure(problem, 'auth/some-new-code');
  @override
  Future<void> registerInstructor(String email, String password) async {
    registerCalls++;
    throw const AuthFailure(AuthProblem.emailInUse);
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<bool> isApprovedInstructor() async => false;
  @override
  Future<String> ensureParticipant() async => 'p';
}

Future<_FailingAuth> _open(
  WidgetTester tester,
  Locale locale, {
  AuthProblem problem = AuthProblem.wrongCredentials,
}) async {
  final auth = _FailingAuth(problem);
  await tester.pumpWidget(
    BouslaApp(
      services: AppServices(
        content: InMemoryContentRepository(),
        sessions: InMemorySessionRepository(),
        auth: auth,
        initialLocale: locale,
      ),
    ),
  );
  await tester.pumpAndSettle();
  final nav = tester.state<NavigatorState>(find.byType(Navigator));
  nav.pushNamed('/instructor');
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  group('authProblemFromCode', () {
    test('maps Firebase codes to problems the UI explains', () {
      expect(authProblemFromCode('invalid-credential'),
          AuthProblem.wrongCredentials);
      expect(
          authProblemFromCode('user-not-found'), AuthProblem.wrongCredentials);
      expect(
          authProblemFromCode('wrong-password'), AuthProblem.wrongCredentials);
      expect(
          authProblemFromCode('email-already-in-use'), AuthProblem.emailInUse);
      expect(authProblemFromCode('weak-password'), AuthProblem.weakPassword);
      expect(authProblemFromCode('invalid-email'), AuthProblem.invalidEmail);
      expect(
          authProblemFromCode('network-request-failed'), AuthProblem.network);
      expect(authProblemFromCode('too-many-requests'),
          AuthProblem.tooManyAttempts);
      expect(
          authProblemFromCode('operation-not-allowed'), AuthProblem.notEnabled);
      expect(authProblemFromCode('something-new'), AuthProblem.unknown);
    });
  });

  testWidgets('wrong credentials suggest creating an account (Arabic)', (
    tester,
  ) async {
    await _open(tester, const Locale('ar'));
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pump();
    expect(find.textContaining('أول مرة؟ اضغط "إنشاء حساب"'), findsOneWidget);
  });

  testWidgets('an existing email suggests signing in (English)', (
    tester,
  ) async {
    final auth = await _open(tester, const Locale('en'));
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(auth.registerCalls, 1);
    expect(
      find.text(
          'An account with this email already exists. Press "Sign in" instead.'),
      findsOneWidget,
    );
  });

  testWidgets('an unknown failure shows its code so it can be diagnosed', (
    tester,
  ) async {
    await _open(tester, const Locale('en'), problem: AuthProblem.unknown);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.textContaining('(auth/some-new-code)'), findsOneWidget);
  });
}
