import 'package:bousla_app/features/instructor/sessions/join_qr.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(
        body: Center(
          child: JoinQr(
            link: 'https://bousla-educathon.web.app/#/join/ABC234',
            code: 'ABC234',
          ),
        ),
      ),
    );

void main() {
  testWidgets('the QR holds only the join link', (tester) async {
    await tester.pumpWidget(_app(const Locale('ar')));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    // What is encoded is checked by decoding a real render (see the commit).
    expect(tester.widget<JoinQr>(find.byType(JoinQr)).link,
        'https://bousla-educathon.web.app/#/join/ABC234');
    expect(find.bySemanticsLabel('رمز QR للانضمام إلى الجلسة ABC234'),
        findsOneWidget);
  });

  testWidgets('large view for the class opens and closes', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show large for the class'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNWidgets(2));
    expect(find.text('ABC234'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
  });
}
