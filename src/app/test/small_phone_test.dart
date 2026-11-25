import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/features/student_web/join_session/join_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> showOnPhone(
  WidgetTester tester,
  AppServices services,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: ValueListenableBuilder<Locale>(
        valueListenable: services.locale,
        builder: (context, locale, _) => MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final locale in const [Locale('ar'), Locale('en')]) {
    testWidgets('join fits a small phone ($locale)', (tester) async {
      final services = AppServices.inMemory(initialLocale: locale);
      await showOnPhone(tester, services, const JoinScreen());
      expect(tester.takeException(), isNull);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
    });

    testWidgets('join stays reachable above the keyboard ($locale)',
        (tester) async {
      final services = AppServices.inMemory(initialLocale: locale);
      await showOnPhone(tester, services, const JoinScreen());
      await tester.showKeyboard(find.byType(TextField));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(find.byType(TextField), 'ABC234');
      await tester.pump(const Duration(milliseconds: 300));

      final join = find.byType(FilledButton);
      expect(tester.getRect(join).bottom, lessThanOrEqualTo(568 - 300));
      expect(join.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a long question survives rotation and language switching ($locale)',
        (tester) async {
      final services = AppServices.inMemory(initialLocale: locale);
      const course = 'database_systems';
      final next = (await services.content.listQuestions(course)).first;
      final prompt = LocalizedText(
        ar: List.filled(10, next.prompt.ar).join(' '),
        en: List.filled(10, next.prompt.en).join(' '),
      );
      final first = await services.content.saveQuestion(
          course,
          QuestionDraft(
            conceptIds: next.conceptIds,
            prompt: prompt,
            options: next.options,
            correctOptionId: next.options.first.id,
          ),
          status: ReviewStatus.approved);
      final session = await services.sessions.createSession(
        courseId: course,
        ownerId: 'teacher',
        questions: [
          QuestionRef(first.id, first.version),
          QuestionRef(next.id, next.version)
        ],
      );
      final participant = await services.sessions.join(session.id);
      await showOnPhone(tester, services,
          AnsweringScreen(session: session, participantId: participant));
      final submit = find.byType(FilledButton);
      final portraitButton = tester.getRect(submit);
      final lastTile = find.byType(ListTile).last;
      await tester.scrollUntilVisible(
          find.text(first.options.last.text
              .of(locale.languageCode == 'ar' ? Language.ar : Language.en)),
          180);
      await tester.ensureVisible(lastTile);
      await tester.pumpAndSettle();
      await tester.tap(lastTile);
      await tester.pump();
      expect(tester.getRect(submit), portraitButton);

      tester.view.physicalSize = const Size(568, 320);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();
      final language = locale.languageCode == 'ar' ? Language.en : Language.ar;
      final chosenText = find.text(first.options.last.text.of(language));
      await tester.scrollUntilVisible(chosenText, 120);
      expect(
          tester
              .widget<ListTile>(find.ancestor(
                  of: chosenText, matching: find.byType(ListTile)))
              .selected,
          isTrue);
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text(next.prompt.of(language)).hitTestable(), findsOneWidget);
      expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .pixels,
          0);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          0.5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('submit stays visible on a small phone ($locale)', (
      tester,
    ) async {
      final services = AppServices.inMemory(initialLocale: locale);
      final questions = await services.content.listQuestions(
        'database_systems',
      );
      final session = await services.sessions.createSession(
        courseId: 'database_systems',
        ownerId: 'teacher',
        questions: [for (final q in questions) QuestionRef(q.id, q.version)],
      );
      final participant = await services.sessions.join(session.id);
      await showOnPhone(
        tester,
        services,
        AnsweringScreen(session: session, participantId: participant),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final submit = find.byType(FilledButton);
      final position = tester.getRect(submit);
      expect(position.bottom, lessThanOrEqualTo(568));
      expect(position.height, greaterThanOrEqualTo(48));
      await tester.drag(find.byType(ListView), const Offset(0, -250));
      await tester.pump();
      expect(tester.getRect(submit), position);
      expect(tester.takeException(), isNull);
    });
  }
}
