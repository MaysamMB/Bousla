import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/shared/widgets/bousla_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The code field is focused on /join, so its blinking cursor never lets
// pumpAndSettle finish: pump for a fixed time instead.
Future<void> _open(WidgetTester tester, String route) async {
  await tester.pumpWidget(
    BouslaApp(services: AppServices.inMemory(initialLocale: const Locale('ar'))),
  );
  await tester.pump(const Duration(milliseconds: 500));
  tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('typing the code: hint to scan the QR with the camera', (
    tester,
  ) async {
    await _open(tester, '/join');
    expect(
      find.text('أو امسح رمز QR المعروض على الشاشة بكاميرا هاتفك'),
      findsOneWidget,
    );
  });

  testWidgets('came from the QR link: no hint, code filled in', (
    tester,
  ) async {
    await _open(tester, '/join/ABC234');
    expect(find.textContaining('امسح رمز QR'), findsNothing);
    expect(find.text('ABC234'), findsOneWidget);
  });

  testWidgets('the join screen shows the mark; long errors are not cut', (
    tester,
  ) async {
    await _open(tester, '/join');
    expect(find.byType(BouslaMark), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.errorMaxLines, greaterThanOrEqualTo(3));
  });

  testWidgets('the join screen opens "My profile", which explains how to start', (
    tester,
  ) async {
    await _open(tester, '/join');
    await tester.tap(find.byKey(const ValueKey('open-profile')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ملفي'), findsWidgets);
    expect(find.textContaining('احفظ تقدّمك (اختياري)'), findsOneWidget);
  });
}
