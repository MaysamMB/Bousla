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
      expect(role.source.kind, CareerSourceKind.esco, reason: role.id);
      expect(role.source.retrieved, isNotNull);
      // Local adverts: counted per skill, never more than the adverts.
      final local = role.localAdverts!;
      expect(local.total, greaterThan(0));
      for (final skill in role.skills) {
        expect(skill.localCount ?? 0, lessThanOrEqualTo(local.total),
            reason: skill.id);
      }
      expect(role.skills.map((s) => s.id).toSet(), hasLength(role.skills.length),
          reason: 'unique skill IDs in ${role.id}');
      for (final skill in role.skills) {
        expect(skill.sourceUri,
            startsWith('http://data.europa.eu/esco/skill/'), reason: skill.id);
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

  testWidgets('ESCO skills: evidence per covered skill, the rest folded',
      (tester) async {
    await _show(tester, _sessions, roles: _bundledRoles());
    expect(find.byKey(const ValueKey('career-source-notice')), findsOneWidget);
    expect(find.byKey(const ValueKey('career-draft-notice')), findsNothing);
    expect(
        find.text('Source: ESCO (European Commission), skills collected on '
            '2026-11-27; Arabic translation by the Bousla team.'),
        findsOneWidget);

    // Database developer (first): ESCO "query languages" has a possible
    // gap through Joins.
    final sql = find.byKey(const ValueKey('skill-query-languages'));
    expect(find.descendant(of: sql, matching: find.text('May need review')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sql, matching: find.textContaining('Joins: May need review')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sql, matching: find.textContaining('Start with: Joins, ')),
        findsOneWidget);

    // "use databases": only part of its concepts shown so far.
    final use = find.byKey(const ValueKey('skill-use-databases'));
    expect(find.descendant(of: use, matching: find.text('Partly shown')),
        findsOneWidget);

    // Coverage said plainly; uncovered skills are one folded list.
    expect(find.text('Bousla courses currently measure 4 of 20.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('skill-perform-backups')), findsNothing);
    expect(find.text('Skills Bousla does not cover yet: 16'), findsOneWidget);
    await tester.tap(find.text('Skills Bousla does not cover yet: 16'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('outside-skill-perform-backups')),
        findsOneWidget);

    // Local adverts (database developer: 10, enough to show).
    final dbms = find.byKey(
        const ValueKey('local-top-database-management-systems'));
    expect(
        find.descendant(
            of: dbms,
            matching: find.textContaining(
                'asked for in 10 of 10 local adverts · Bousla measures it')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('local-count-query-languages')))
            .data,
        'asked for in 9 of 10 local adverts');
    expect(find.text('One person linked the adverts to skills; not '
        'cross-checked yet.'), findsOneWidget);

    // Data analyst.
    await tester.tap(find.byKey(const ValueKey('role-data_analyst')));
    await tester.pumpAndSettle();
    expect(find.text('Bousla courses currently measure 4 of 36.'),
        findsOneWidget);
    expect(find.text('Bousla courses currently measure 2 of 14.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('skill-normalise-data')), findsOneWidget);
    // 9 local adverts: fewer than 10, so no local numbers yet.
    expect(find.byKey(const ValueKey('career-local-too-few')), findsOneWidget);
    expect(find.textContaining('We have collected 9 local adverts'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('local-count-query-languages')),
        findsNothing);
    expect(find.byKey(const ValueKey('career-next')), findsOneWidget);
    // The next step opens its (front-end only) screen.
    await tester.tap(find.text('Add a course from outside Bousla (preview)'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('external-preview-notice')), findsOneWidget);
  });

  testWidgets('a team-draft dataset says it is a draft', (tester) async {
    await _show(tester, _sessions, roles: [
      careerRoleFromJson({
        'id': 'draft',
        'title': {'ar': 'مسودة', 'en': 'Draft role'},
        'source': {'kind': 'team_draft', 'name': 'Team draft'},
        'skills': [
          {
            'id': 'sql',
            'name': {'ar': 'SQL', 'en': 'SQL'},
            'essential': true,
            'concepts': ['sql_select'],
          },
        ],
      }),
    ]);
    expect(find.byKey(const ValueKey('career-draft-notice')), findsOneWidget);
    expect(find.text('Shown in your sessions'), findsOneWidget);
  });
}
