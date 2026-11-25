import 'package:bousla_app/features/instructor/sessions/insights_presentation_layout.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(String locale, {Key? sessionKey}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: InsightsPresentationLayout(
    key: sessionKey,
    builder: (context, presentationMode) => Column(children: [
      Text('Aggregate evidence', style: Theme.of(context).textTheme.titleLarge),
      if (!presentationMode) const Text('Detailed chart and draft'),
    ]),
  ))),
);

void main() {
  testWidgets('presentation toggles detail visibility and enlarges summary', (tester) async {
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    final summary = find.text('Aggregate evidence');
    final before = tester.widget<Text>(summary).style!.fontSize!;
    expect(find.text('Detailed chart and draft'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(summary, findsOneWidget);
    expect(find.text('Detailed chart and draft'), findsNothing);
    expect(tester.widget<Text>(summary).style!.fontSize!, greaterThan(before));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Detailed chart and draft'), findsOneWidget);
  });
  testWidgets('Arabic presentation control remains RTL on small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app('ar'));
    await tester.pumpAndSettle();
    expect(Directionality.of(tester.element(find.text('وضع العرض'))), TextDirection.rtl);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Detailed chart and draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a new session starts with the normal view', (tester) async {
    await tester.pumpWidget(app('en', sessionKey: const ValueKey('a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app('en', sessionKey: const ValueKey('b')));
    await tester.pumpAndSettle();
    expect(find.text('Detailed chart and draft'), findsOneWidget);
  });
}
