import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/data/session_title.dart';
import 'package:bousla_app/features/instructor/sessions/create_session_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionView _q(String id, List<String> concepts) => QuestionView(
      question: Question(
        id: id,
        version: 1,
        conceptIds: concepts,
        optionIds: const ['a', 'b'],
      ),
      prompt: const LocalizedText(ar: 'س', en: 'Q'),
      options: const [],
      source: ContentSource.team,
      edited: false,
    );

const _concepts = [
  Concept(id: 'pk', name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key')),
  Concept(id: 'fk', name: LocalizedText(ar: 'المفتاح الأجنبي', en: 'Foreign Key')),
  Concept(id: 'sql', name: LocalizedText(ar: 'SQL', en: 'SQL')),
  Concept(id: 'nf', name: LocalizedText(ar: 'التطبيع', en: 'Normalization')),
];

void main() {
  group('sessionTitleFor', () {
    test('concepts in question order, two shown, the rest counted', () {
      final t = sessionTitleFor([
        _q('1', ['pk']),
        _q('2', ['fk', 'pk']),
        _q('3', ['sql']),
        _q('4', ['nf', 'unknown']),
      ], _concepts);
      expect(t.en, 'Primary Key, Foreign Key +2');
      expect(t.ar, 'المفتاح الأساسي، المفتاح الأجنبي \u2066+2\u2069');
    });

    test('one concept; no known concept', () {
      expect(sessionTitleFor([_q('1', ['pk'])], _concepts).en, 'Primary Key');
      expect(sessionTitleFor(const [], _concepts).ar, 'جلسة');
    });
  });

  test('in-memory: newest first, own course only, keeps title and time',
      () async {
    final services = AppServices.inMemory();
    final sessions = services.sessions;
    final a = await sessions.createSession(
      courseId: 'c1',
      ownerId: 't',
      questions: const [],
      title: const LocalizedText(ar: 'أ', en: 'A'),
    );
    await sessions.createSession(courseId: 'c2', ownerId: 't', questions: const []);
    await sessions.createSession(courseId: 'c1', ownerId: 'other', questions: const []);
    final b = await sessions.createSession(courseId: 'c1', ownerId: 't', questions: const []);
    await sessions.closeSession(a.id);
    final list = await sessions.listSessions(ownerId: 't', courseId: 'c1');
    expect([for (final s in list) s.id], [b.id, a.id]);
    expect(list.last.title?.en, 'A');
    expect(list.last.createdAt, isNotNull);
    expect(list.last.closedAt, isNotNull);
    expect(list.last.status, SessionStatus.closed);
  });

  testWidgets('past sessions: titled list, then the results of one',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const CreateSessionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Past sessions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No sessions yet'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create session'));
    await tester.pumpAndSettle();
    final created = (await services.sessions.listSessions(
      ownerId: services.auth.instructorId!,
      courseId: 'database_systems',
    ))
        .single;
    final title = created.title!.en;
    expect(title, isNot('Session'));

    await tester.tap(find.byTooltip('Past sessions'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Join code: \u2066${created.code}\u2069'), findsOneWidget);

    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.text('Session results'), findsOneWidget);
    expect(find.text('What the class understands'), findsOneWidget);
  });

  testWidgets('the instructor renames a session from its results',
      (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await services.sessions.createSession(
      courseId: 'database_systems',
      ownerId: services.auth.instructorId!,
      questions: const [],
      title: const LocalizedText(ar: 'قديم', en: 'Old title'),
    );
    await tester.pumpWidget(
      ServicesScope(
        services: services,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const CreateSessionScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Past sessions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Rename session'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'مراجعة المفاتيح');
    // English left empty: the Arabic title is used for both.
    await tester.enterText(fields.at(1), '');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save'));
    // A text field was focused: pump a fixed time instead of settling.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('مراجعة المفاتيح'), findsOneWidget);

    await tester.pageBack();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Past sessions'), findsOneWidget);
    expect(find.text('مراجعة المفاتيح'), findsOneWidget);
    final stored = (await services.sessions.listSessions(
      ownerId: services.auth.instructorId!,
      courseId: 'database_systems',
    ))
        .single
        .title!;
    expect((stored.ar, stored.en), ('مراجعة المفاتيح', 'مراجعة المفاتيح'));
  });
}
