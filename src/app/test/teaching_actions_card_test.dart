import 'package:bousla_app/features/instructor/sessions/teaching_actions_card.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(String language, {bool suppressed = false}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: TeachingActionsCard(
    insights: ClassInsights(participantCount: suppressed ? 4 : 8,
      minGroupSize: 5, prerequisiteSignals: const [], concepts: [
        ConceptClassSummary(conceptId: 'pk', respondents: suppressed ? 4 : 8,
          suppressed: suppressed, stateCounts: suppressed ? const {} : const {
            MasteryState.possibleDifficulty: 6, MasteryState.emerging: 2,
          }),
      ]),
    coveredConceptIds: const {'pk'},
    conceptNames: {'pk': language == 'ar' ? 'المفتاح الأساسي' : 'Primary Key'},
  ))),
);

void main() {
  testWidgets('English action shows its real aggregate evidence', (tester) async {
    await tester.pumpWidget(app('en'));
    await tester.pumpAndSettle();
    expect(find.text('Review Primary Key'), findsOneWidget);
    expect(find.text('6 of 8 respondents show possible difficulty.'), findsOneWidget);
  });
  testWidgets('Arabic action uses RTL and fits a small viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app('ar'));
    await tester.pumpAndSettle();
    final title = find.text('راجع المفتاح الأساسي');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no action card is shown for a suppressed concept', (tester) async {
    await tester.pumpWidget(app('en', suppressed: true));
    await tester.pumpAndSettle();
    expect(find.text('Suggested teaching actions'), findsNothing);
  });
}
