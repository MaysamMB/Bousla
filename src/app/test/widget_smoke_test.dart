import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts in Arabic (RTL) and switches to English (LTR)', (
    tester,
  ) async {
    await tester.pumpWidget(BouslaApp(services: AppServices.inMemory()));
    await tester.pumpAndSettle();

    expect(find.text('أنا مدرّس'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('أنا مدرّس'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.text("I'm an instructor"), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text("I'm an instructor"))),
      TextDirection.ltr,
    );
  });

  testWidgets('instructor screen shows live counts when a student answers', (
    tester,
  ) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();
    expect(find.text('Students who answered: 0 · Answers: 0'), findsOneWidget);

    final code = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .first
        .data!;
    final session = (await services.sessions.findByCode(code))!;
    final participant = await services.sessions.join(session.id);
    final question = (await services.content.listQuestions(session.courseId))
        .first;
    await services.sessions.submitResponse(
      session.id,
      Response(
        participantId: participant,
        questionId: question.id,
        questionVersion: question.version,
        selectedOptionId: question.options.first.id,
        displayLanguage: Language.en,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Students who answered: 1 · Answers: 1'), findsOneWidget);
  });

  // Repository calls that are not driven by the UI run in tester.runAsync, and
  // the code field is unfocused before tapping "join" so its blinking cursor
  // cannot keep the test busy.
  testWidgets('a student joins by code and answers in Arabic', (tester) async {
    Future<void> pumpFor(Duration d) async {
      await tester.pump();
      await tester.pump(d);
    }

    final services = AppServices.inMemory();
    final session = (await tester.runAsync(() async {
      final questions = await services.content.listQuestions(
        'database_systems',
      );
      return services.sessions.createSession(
        courseId: 'database_systems',
        ownerId: 'teacher',
        questions: [for (final q in questions) QuestionRef(q.id, q.version)],
      );
    }))!;

    await tester.pumpWidget(BouslaApp(services: services));
    await pumpFor(const Duration(milliseconds: 500));

    await tester.tap(find.text('الانضمام إلى جلسة'));
    await pumpFor(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField), session.code.toLowerCase());
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(find.text('انضمام'));
    await pumpFor(const Duration(seconds: 1));
    await pumpFor(const Duration(seconds: 1));

    expect(find.text('السؤال 1 من 4'), findsOneWidget);
    await tester.tap(
      find.text('أن يكون فريداً ولا يقبل القيمة الفارغة (NULL)'),
    );
    await tester.pump();

    await tester.tap(find.text('إرسال'));
    await pumpFor(const Duration(seconds: 1));
    expect(find.text('السؤال 2 من 4'), findsOneWidget);

    final responses = (await tester.runAsync(
      () => services.sessions.watchResponses(session.id).first,
    ))!;
    expect(responses.single.displayLanguage, Language.ar);
    expect(responses.single.selectedOptionId, 'a');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('the offline demo mode shows a banner; Firebase mode does not', (
    tester,
  ) async {
    await tester.pumpWidget(BouslaApp(services: AppServices.inMemory()));
    await tester.pumpAndSettle();
    expect(find.byType(Banner), findsOneWidget);
    expect(
      tester.widget<Banner>(find.byType(Banner)).message,
      'عرض محلي',
    );

    final services = AppServices.inMemory();
    await tester.pumpWidget(
      BouslaApp(
        services: AppServices(
          content: services.content,
          sessions: services.sessions,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Banner), findsNothing);
  });
}
