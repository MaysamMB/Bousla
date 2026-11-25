import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/features/instructor/content_review/question_editor_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

Future<AppServices> _open(WidgetTester tester, {Locale ui = const Locale('ar')}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.inMemory(initialLocale: ui);
  final concepts = await services.content.listConcepts(_course);
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: MaterialApp(
        locale: ui,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: QuestionEditorScreen(courseId: _course, concepts: concepts),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

Future<void> _fill(WidgetTester tester, String prompt, String a, String b) async {
  await tester.enterText(find.byKey(const ValueKey('prompt')), prompt);
  await tester.enterText(find.byKey(const ValueKey('option-a')), a);
  await tester.enterText(find.byKey(const ValueKey('option-b')), b);
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.text('المفتاح الأساسي').last);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(find.byType(ChoiceChip).at(1));
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('حفظ'));
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('one box: an English question is saved for both languages',
      (tester) async {
    final services = await _open(tester);
    // Only one box per text until a translation is asked for.
    expect(find.byKey(const ValueKey('prompt-translation')), findsNothing);
    await _fill(tester, 'Can a primary key be NULL?', 'Yes', 'No');
    await _save(tester);
    final q = (await services.content.listQuestions(_course,
            approvedOnly: false))
        .firstWhere((q) => q.prompt.en == 'Can a primary key be NULL?');
    expect(q.prompt.ar, 'Can a primary key be NULL?');
    expect(q.options.map((o) => o.text.ar), ['Yes', 'No']);
    expect(q.options.map((o) => o.text.en), ['Yes', 'No']);
  });

  testWidgets('with a translation: Arabic text and its English translation',
      (tester) async {
    final services = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('translate')));
    await tester.pump();
    // Nothing typed yet, Arabic interface: the translation is English.
    expect(find.text('الترجمة الإنجليزية'), findsWidgets);
    await _fill(tester, 'هل يقبل المفتاح الأساسي القيمة الفارغة؟', 'نعم', 'لا');
    // The main text is Arabic, so the translation box asks for English.
    expect(find.text('الترجمة الإنجليزية'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('prompt-translation')),
      'Can a primary key be NULL?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('option-a-translation')),
      'Yes',
    );
    // Option b left untranslated: the same text in both.
    await _save(tester);
    final q = (await services.content.listQuestions(_course,
            approvedOnly: false))
        .firstWhere((q) => q.prompt.en == 'Can a primary key be NULL?');
    expect(q.prompt.ar, 'هل يقبل المفتاح الأساسي القيمة الفارغة؟');
    expect(q.options[0].text.ar, 'نعم');
    expect(q.options[0].text.en, 'Yes');
    expect(q.options[1].text.en, 'لا');
  });
}
