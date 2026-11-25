import 'package:bousla_app/features/instructor/sessions/concept_overview_card.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(String language, {bool allHidden = false, double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: ConceptOverviewCard(
    insights: ClassInsights(participantCount: 8, minGroupSize: 5,
      prerequisiteSignals: const [], concepts: [
        ConceptClassSummary(conceptId: 'pk', respondents: allHidden ? 4 : 8,
          suppressed: allHidden, stateCounts: allHidden ? const {} : const {
            MasteryState.possibleDifficulty: 6, MasteryState.emerging: 2,
          }),
        const ConceptClassSummary(conceptId: 'hidden', respondents: 4,
            suppressed: true),
      ]),
    coveredConceptIds: const {'pk', 'hidden'},
    conceptNames: {'pk': language == 'ar' ? 'المفتاح الأساسي' : 'Primary Key',
      'hidden': 'Hidden concept'},
  ))),
);

void main() {
  testWidgets('comparison displays evidence with text, not just colors', (tester) async {
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    expect(find.text('Primary Key'), findsOneWidget);
    expect(find.text('Possible difficulty: 6 (75%)'), findsOneWidget);
    expect(find.text('8 respondents'), findsOneWidget);
    expect(find.text('Hidden concept'), findsNothing);
    expect(find.text('Concepts not displayed: 1'), findsOneWidget);
  });
  testWidgets('all suppressed means no comparison values', (tester) async {
    await tester.pumpWidget(app('en', allHidden: true));
    await tester.pumpAndSettle();
    expect(find.text('Primary Key'), findsNothing);
    expect(find.text('4 respondents'), findsNothing);
    expect(find.text('No concept has enough respondents to display yet.'),
        findsOneWidget);
  });
  testWidgets('Arabic layout works on narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app('ar', textScale: 1.3));
    await tester.pumpAndSettle();
    final title = find.text('ملخص مفاهيم الصف');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
