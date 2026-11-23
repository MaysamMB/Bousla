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
    expect(find.text('0 participants · 0 answers'), findsOneWidget);

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
    expect(find.text('1 participants · 1 answers'), findsOneWidget);
  });

  // The join screen focuses the code field, and a blinking cursor keeps
  // scheduling frames, so pumpAndSettle() would never return here. This test
  // pumps for fixed durations instead.
  testWidgets('a student joins by code and answers in Arabic', (tester) async {
    Future<void> settleWithCursor() async {
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    final services = AppServices.inMemory();
    final session = await services.sessions.createSession(
      courseId: 'database_systems',
      ownerId: 'teacher',
      questions: [
        for (final q in await services.content.listQuestions(
          'database_systems',
        ))
          QuestionRef(q.id, q.version),
      ],
    );
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الانضمام إلى جلسة'));
    await settleWithCursor();
    await tester.enterText(find.byType(TextField), session.code.toLowerCase());
    await tester.tap(find.text('انضمام'));
    await settleWithCursor();
    await settleWithCursor();

    expect(find.text('السؤال 1 من 4'), findsOneWidget);
    await tester.tap(
      find.text('أن يكون فريداً ولا يقبل القيمة الفارغة (NULL)'),
    );
    await tester.pump();
    await tester.tap(find.text('إرسال'));
    await settleWithCursor();
    expect(find.text('السؤال 2 من 4'), findsOneWidget);

    final responses = await services.sessions.watchResponses(session.id).first;
    expect(responses.single.displayLanguage, Language.ar);
    expect(responses.single.selectedOptionId, 'a');
  }, timeout: const Timeout(Duration(seconds: 60)));
}
