import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/sessions/share_feedback.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _session = Session(
  id: 'ABC234',
  code: 'ABC234',
  courseId: 'database_systems',
  ownerId: 'teacher',
  questions: [],
  status: SessionStatus.closed,
  feedbackReleased: true,
  title: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
);

void main() {
  test('the message has both languages, the title, code and link', () {
    final m = shareFeedbackMessage(
      _session,
      link: 'https://example.web.app/#/join/ABC234',
    );
    expect(m, contains('«المفتاح الأساسي»'));
    expect(m, contains('«Primary Key»'));
    expect(m, contains('نفس الهاتف'));
    expect(m, contains('same phone'));
    expect('ABC234'.allMatches(m).length, greaterThanOrEqualTo(2));
    expect('https://example.web.app/#/join/ABC234'.allMatches(m).length, 2);
  });

  testWidgets('the share sheet shows the message and ways to send it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ar'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: Center(child: ShareFeedbackButton(session: _session))),
    ));
    await tester.tap(find.text('مشاركة الرابط مع الطلاب'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-message')), findsOneWidget);
    expect(find.text('نسخ الرسالة'), findsOneWidget);
    expect(find.text('مشاركة…'), findsOneWidget);
  });
}
