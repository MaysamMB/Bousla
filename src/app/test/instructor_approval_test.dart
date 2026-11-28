import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/repositories/auth_service.dart';
import 'package:bousla_app/features/instructor/auth/instructor_gate.dart'
    show adminEmail;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A signed-in instructor account whose approval can be switched on.
class _PendingAuth implements AuthService {
  @override
  StudentAccount? get studentAccount => null;

  @override
  Future<StudentAccount> linkStudentAccount() =>
      throw const StudentLinkFailure(StudentLinkProblem.unknown);

  @override
  Future<StudentAccount> switchToLinkedStudentAccount() =>
      throw const StudentLinkFailure(StudentLinkProblem.unknown);

  var approved = false;
  var signedOut = false;

  @override
  bool get requiresSignIn => true;
  @override
  String? get instructorId => 'uid-123';
  @override
  Stream<String?> instructorChanges() => Stream.value('uid-123');
  @override
  Future<void> signInInstructor(String email, String password) async {}
  @override
  Future<void> registerInstructor(String email, String password) async {}
  @override
  Future<void> signOut() async => signedOut = true;
  @override
  Future<bool> isApprovedInstructor() async => approved;
  @override
  Future<String> ensureParticipant() async => 'p';
}

Future<_PendingAuth> _open(WidgetTester tester, Locale locale) async {
  final auth = _PendingAuth();
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
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/instructor');
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('unapproved account waits, sees its ID, then gets in', (
    tester,
  ) async {
    final auth = await _open(tester, const Locale('en'));
    expect(find.text('Account waiting for approval'), findsOneWidget);
    expect(find.text('uid-123'), findsOneWidget);
    // Who to ask, not how the project is set up.
    expect(find.text(adminEmail), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.text('Email the administrator'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await tester.ensureVisible(find.text('Copy the request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy the request'));
    await tester.pumpAndSettle();
    expect(copied, contains('uid-123'));
    expect(copied, contains(adminEmail));
    expect(find.textContaining('Request copied'), findsOneWidget);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    ScaffoldMessenger.of(tester.element(find.text('Check again')))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    expect(find.text('Create session'), findsNothing);

    // Still not approved: stays on the waiting screen.
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Account waiting for approval'), findsOneWidget);

    auth.approved = true;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Create session'), findsOneWidget);
  });

  testWidgets('waiting screen in Arabic, with sign out', (tester) async {
    final auth = await _open(tester, const Locale('ar'));
    expect(find.text('الحساب بانتظار الاعتماد'), findsOneWidget);
    expect(find.text('راسل المسؤول'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    await tester.tap(find.text('تسجيل الخروج'));
    await tester.pumpAndSettle();
    expect(auth.signedOut, isTrue);
  });
}
