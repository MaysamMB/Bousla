// "Add a course from outside Bousla": front end only. Nothing is uploaded
// or saved; continuing says the step is not built yet.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/features/student_web/career/external_course_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(
    WidgetTester tester, Future<PickedOutline?> Function() pick) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ServicesScope(
    services: AppServices.inMemory(initialLocale: const Locale('en')),
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ExternalCourseScreen(pickOutline: pick),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('says it is a preview; asks for a name and an outline',
      (tester) async {
    await _show(tester, () async => null);
    expect(
        find.byKey(const ValueKey('external-preview-notice')), findsOneWidget);
    expect(find.text('What happens next'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('external-continue')));
    await tester.pump();
    expect(find.text('Enter the course name.'), findsOneWidget);
    expect(
        find.text('Add the outline file or paste its topics.'), findsOneWidget);
    expect(find.byKey(const ValueKey('external-not-ready')), findsNothing);
  });

  testWidgets(
      'a picked file is shown and can be removed; continuing says '
      'nothing was uploaded', (tester) async {
    await _show(tester,
        () async => const PickedOutline(name: 'ds-outline.pdf', bytes: 250000));
    await tester.enterText(
        find.byKey(const ValueKey('external-name')), 'Data Structures');
    await tester.tap(find.byKey(const ValueKey('external-pick')));
    await tester.pump();
    expect(find.text('ds-outline.pdf'), findsOneWidget);
    expect(find.text('245 KB'), findsOneWidget);
    expect(find.text('Choose another file'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('external-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('external-not-ready')), findsOneWidget);
    expect(find.textContaining('Your file was not uploaded'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Remove the file'));
    await tester.pump();
    expect(find.text('ds-outline.pdf'), findsNothing);
  });

  testWidgets('pasted topics are enough instead of a file', (tester) async {
    await _show(tester, () async => null);
    await tester.enterText(
        find.byKey(const ValueKey('external-name')), 'هياكل البيانات');
    await tester.enterText(
        find.byKey(const ValueKey('external-paste')), 'Stacks; queues; trees');
    await tester.tap(find.byKey(const ValueKey('external-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('external-not-ready')), findsOneWidget);
  });
}
