// Career path preview: the bundled datasets and the screen.
import 'dart:convert';
import 'dart:io';

import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/careers.dart';
import 'package:bousla_app/data/repositories/profile_repository.dart';
import 'package:bousla_app/features/student_web/career/career_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

SavedConcept _c(String id, String en, MasteryState state, int a, int c) =>
    SavedConcept(
      conceptId: id,
      name: LocalizedText(ar: en, en: en),
      state: state,
      attempts: a,
      correct: c,
    );

final _sessions = [
  SavedSession(
    code: 'S1',
    courseId: 'database_systems',
    concepts: [
      _c('sql_select', 'Basic SELECT Queries', MasteryState.demonstratedMastery, 3, 3),
      _c('sql_join', 'Joins', MasteryState.possibleDifficulty, 4, 1),
      _c('primary_key', 'Primary Key', MasteryState.demonstratedMastery, 3, 3),
    ],
  ),
];

Future<void> _show(WidgetTester tester, List<SavedSession> sessions,
    {List<CareerRole>? roles}) async {
  tester.view.physicalSize = const Size(800, 4000);
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
      home: CareerScreen(sessions: sessions, roles: roles),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

List<CareerRole> _bundledRoles() => [
      for (final path in careerRoleAssets)
        careerRoleFromJson(
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>),
    ];

void main() {
  test('every dataset names its source and maps only to real concept IDs', () {
    final course = {
      for (final c in jsonDecode(File(
              '../../data/courses/database-systems/concepts.json')
          .readAsStringSync()) as List)
        (c as Map)['id'] as String: c['name'] as Map,
    };
    final concepts = course.keys.toSet();
    final roles = _bundledRoles();
    expect(roles, hasLength(2));
    for (final role in roles) {
      expect(role.source.name, isNotEmpty);
      expect(role.skills.map((s) => s.id).toSet(), hasLength(role.skills.length),
          reason: 'unique skill IDs in ${role.id}');
      for (final skill in role.skills) {
        expect(skill.name.ar, isNotEmpty);
        expect(skill.name.en, isNotEmpty);
        for (final id in skill.conceptIds) {
          expect(concepts, contains(id), reason: '${role.id}/${skill.id}');
          // Its name is carried, and is the course's own name.
          expect(role.conceptNames[id]?.ar, course[id]!['ar'], reason: id);
          expect(role.conceptNames[id]?.en, course[id]!['en'], reason: id);
        }
      }
    }
  });

  testWidgets('no saved session: asks for one first', (tester) async {
    await _show(tester, const []);
    expect(find.text('Add at least one session to your profile to see your '
        'career path.'), findsOneWidget);
  });

  testWidgets('a draft dataset says so; each skill shows its evidence',
      (tester) async {
    await _show(tester, _sessions, roles: _bundledRoles());
    expect(find.byKey(const ValueKey('career-draft-notice')), findsOneWidget);

    // Database developer (first): SQL has a possible gap through Joins.
    final sql = find.byKey(const ValueKey('skill-sql_querying'));
    expect(find.descendant(of: sql, matching: find.text('May need review')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sql, matching: find.textContaining('Joins: May need review')),
        findsOneWidget);
    // Review first, then the concepts that need evidence.
    expect(
        find.descendant(
            of: sql, matching: find.textContaining('Start with: Joins, ')),
        findsOneWidget);
    // A concept never asked about gets its name from the course.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('skill-keys_integrity')),
            matching: find.text('Start with: Foreign Key')),
        findsOneWidget);

    // Keys: only Primary Key shown so far.
    final keys = find.byKey(const ValueKey('skill-keys_integrity'));
    expect(find.descendant(of: keys, matching: find.text('Partly shown')),
        findsOneWidget);

    // A skill no Bousla course covers says so, without a judgement.
    final git = find.byKey(const ValueKey('skill-version_control'));
    expect(find.descendant(
            of: git, matching: find.text('Not covered by Bousla courses yet')),
        findsOneWidget);

    // Data analyst.
    await tester.tap(find.byKey(const ValueKey('role-data_analyst')));
    await tester.pump();
    expect(find.byKey(const ValueKey('skill-statistics')), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-version_control')), findsNothing);
    expect(find.byKey(const ValueKey('career-next')), findsOneWidget);
  });
}
