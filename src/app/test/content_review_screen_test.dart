import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/student_web/answering/answering_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Only taps, no typing: a focused text field's blinking cursor keeps
// pumpAndSettle busy (see widget_smoke_test.dart).
void main() {
  Future<AppServices> openReview(WidgetTester tester) async {
    // A tall screen keeps both draft cards built: once a draft is selected,
    // the bottom action bar takes space and the second card could leave the
    // list's build area.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review questions'));
    await tester.pumpAndSettle();
    return services;
  }

  Future<void> tapFirst(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('instructor approves one AI draft and rejects the other', (
    tester,
  ) async {
    final services = await openReview(tester);

    expect(find.text('Waiting (2)'), findsOneWidget);
    expect(find.text('Approved (4)'), findsOneWidget);
    expect(find.text('AI draft'), findsWidgets);

    await tapFirst(tester, 'Approve');
    expect(find.text('Waiting (1)'), findsOneWidget);
    expect(find.text('Approved (5)'), findsOneWidget);

    await tapFirst(tester, 'Reject');
    expect(find.text('Reject questions (1)'), findsOneWidget);
    await tester.tap(find.text('Unclear wording'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Rejected (1)'), findsOneWidget);
    expect(find.textContaining('rejected 1'), findsOneWidget);

    final all = await tester.runAsync(
      () => services.content.listQuestions(
        'database_systems',
        approvedOnly: false,
      ),
    );
    final rejected = all!.singleWhere((q) => q.id == 'db_rm_002');
    expect(rejected.status, ReviewStatus.rejected);
    expect(rejected.rejectionReason, RejectionReason.unclear);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('instructor selects drafts and rejects them together', (
    tester,
  ) async {
    await openReview(tester);

    await tester.tap(find.byKey(const ValueKey('select-db_rm_001')));
    await tester.pumpAndSettle();
    expect(find.text('Reject selected (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('select-db_rm_002')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reject selected (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject without a reason'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Rejected (2)'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('hide Arabic answers in all questions, then show them again', (
    tester,
  ) async {
    final services = await openReview(tester);
    Future<List<QuestionView>> all() async => (await tester.runAsync(
      () => services.content.listQuestions(
        'database_systems',
        approvedOnly: false,
      ),
    ))!;

    await tester.tap(find.byKey(const ValueKey('hide-ar-all')));
    await tester.pumpAndSettle();
    expect(
      (await all()).every(
        (q) => q.hiddenOptionLanguages.contains(Language.ar),
      ),
      isTrue,
    );

    // English for all: Arabic becomes visible again everywhere.
    await tester.tap(find.byKey(const ValueKey('hide-en-all')));
    await tester.pumpAndSettle();
    expect(
      (await all()).every(
        (q) =>
            q.hiddenOptionLanguages.length == 1 &&
            q.hiddenOptionLanguages.contains(Language.en),
      ),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('hide-en-all')));
    await tester.pumpAndSettle();
    expect(
      (await all()).every((q) => q.hiddenOptionLanguages.isEmpty),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'a student in Arabic sees English answers when Arabic is hidden',
    (tester) async {
      final services = AppServices.inMemory();
      final session = (await tester.runAsync(() async {
        await services.content.setOptionLanguageHidden(
          'database_systems',
          ['db_pk_001'],
          Language.ar,
          hidden: true,
        );
        final questions = await services.content.listQuestions(
          'database_systems',
        );
        return services.sessions.createSession(
          courseId: 'database_systems',
          ownerId: 'teacher',
          questions: [for (final q in questions) QuestionRef(q.id, q.version)],
        );
      }))!;

      await tester.pumpWidget(
        ServicesScope(
          services: services,
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: AnsweringScreen(session: session, participantId: 'p1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The question stays in Arabic; its answers are shown in English.
      expect(
        find.text('أيّ خاصية يجب أن يحققها المفتاح الأساسي (Primary Key)؟'),
        findsOneWidget,
      );
      expect(find.text('Unique and not NULL'), findsOneWidget);
      expect(
        find.text('أن يكون فريداً ولا يقبل القيمة الفارغة (NULL)'),
        findsNothing,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
