import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/features/student_web/join_session/join_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
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
      child: MaterialApp(
        locale: services.locale.value,
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
