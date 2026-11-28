// Career path screen: "Local job market" and "Essential skills" are folded
// by default; inside "Essential skills" the skills are grouped by the status
// the engine already gives them (careerGaps, unchanged).
import 'dart:convert';
import 'dart:io';

import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/careers.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/repositories/content_repository.dart';
import 'package:bousla_app/data/repositories/profile_repository.dart';
import 'package:bousla_app/features/student_web/career/career_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts the concept reads the screen makes (the only repository call it
/// does); everything else goes to the in-memory repository.
class _CountingContent implements ContentRepository {
  final _inner = InMemoryContentRepository();
  var conceptReads = 0;

  @override
  Future<List<Concept>> listConcepts(String courseId) {
    conceptReads++;
    return _inner.listConcepts(courseId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

SavedConcept _c(String id, MasteryState state, int a, int c) => SavedConcept(
      conceptId: id,
      name: LocalizedText(ar: id, en: id),
      state: state,
      attempts: a,
      correct: c,
    );

final _sessions = [
  SavedSession(
    code: 'S1',
    courseId: 'database_systems',
    concepts: [
      _c('sql_select', MasteryState.demonstratedMastery, 3, 3),
      _c('sql_join', MasteryState.possibleDifficulty, 4, 1),
      _c('primary_key', MasteryState.demonstratedMastery, 3, 3),
    ],
  ),
];

List<CareerRole> _bundledRoles() => [
      for (final path in careerRoleAssets)
        careerRoleFromJson(
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>),
    ];

/// One role with an essential skill in every status the engine can give.
CareerRole _everyStatusRole() => careerRoleFromJson({
      'id': 'r',
      'title': {'ar': 'دور', 'en': 'Role'},
      'source': {'kind': 'team_draft', 'name': 'Team draft'},
      'skills': [
        for (final (id, concepts) in [
          ('shown', ['sql_select']),
          ('gap', ['sql_join']),
          ('partly', ['sql_select', 'normalization']),
          ('none', ['normalization']),
          ('outside', <String>[]),
        ])
          {
            'id': id,
            'name': {'ar': 'مهارة $id', 'en': 'Skill $id'},
            'essential': true,
            'concepts': concepts,
          },
      ],
    });

Future<_CountingContent> _show(
  WidgetTester tester,
  List<CareerRole> roles, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final content = _CountingContent();
  // A fresh tree each time, so no section state carries over.
  await tester.pumpWidget(KeyedSubtree(
      key: UniqueKey(),
      child: ServicesScope(
        services: AppServices(
          content: content,
          sessions: InMemorySessionRepository(),
          initialLocale: Locale(locale),
        ),
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CareerScreen(sessions: _sessions, roles: roles),
        ),
      )));
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
  return content;
}

final _local = find.text('Local job market');
final _essential = find.text('Essential skills');

void main() {
  testWidgets('local market: closed by default, opens and closes on tap',
      (tester) async {
    final content = await _show(tester, _bundledRoles());
    final role = _bundledRoles().first;
    final top = role.topLocalSkills();
    expect(top, isNotEmpty);

    // Closed: the title and its arrow, no adverts.
    expect(_local, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('career-local')),
            matching: find.byIcon(Icons.expand_more)),
        findsOneWidget);
    expect(find.byKey(ValueKey('local-top-${top.first.id}')), findsNothing);

    await tester.tap(_local);
    await tester.pumpAndSettle();
    // Every advert line is there, unchanged.
    for (final s in top) {
      expect(find.byKey(ValueKey('local-top-${s.id}')), findsOneWidget);
    }
    expect(
        find.descendant(
            of: find
                .byKey(const ValueKey('local-top-database-management-systems')),
            matching: find.textContaining(
                'asked for in 10 of 10 local adverts · Bousla measures it')),
        findsOneWidget);

    await tester.tap(_local);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('local-top-${top.first.id}')), findsNothing);

    // Opening and closing read nothing again: one read per course, at load.
    expect(content.conceptReads, 1);
  });

  testWidgets('essential skills: closed by default, grouped once opened',
      (tester) async {
    final content = await _show(tester, [_everyStatusRole()]);
    expect(_essential, findsOneWidget);
    expect(find.byKey(const ValueKey('coverage-essential')), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-shown')), findsNothing);
    expect(find.byKey(const ValueKey('skill-group-evidence')), findsNothing);

    await tester.tap(_essential);
    await tester.pumpAndSettle();

    // Each skill sits under the status the engine gave it.
    final report =
        careerGaps(_everyStatusRole(), standingsFromSessions(_sessions));
    final byId = {for (final s in report.skills) s.skill.id: s.status};
    expect(byId, {
      'shown': SkillStatus.evidence,
      'gap': SkillStatus.possibleGap,
      'partly': SkillStatus.partial,
      'none': SkillStatus.noEvidence,
      'outside': SkillStatus.outsideBousla,
    });
    for (final MapEntry(key: id, value: status) in byId.entries) {
      if (status == SkillStatus.outsideBousla) continue;
      expect(
          find.descendant(
              of: find.byKey(ValueKey('skill-group-${status.name}')),
              matching: find.byKey(ValueKey('skill-$id'))),
          findsOneWidget,
          reason: id);
    }
    // Headings with their counts, in the engine's status order.
    expect(find.text('May need review (1)'), findsOneWidget);
    expect(find.text('No evidence yet (1)'), findsOneWidget);
    expect(find.text('Partly shown (1)'), findsOneWidget);
    expect(find.text('Shown in your sessions (1)'), findsOneWidget);
    final order = [
      for (final st in ['possibleGap', 'noEvidence', 'partial', 'evidence'])
        tester.getTopLeft(find.byKey(ValueKey('skill-group-$st'))).dy,
    ];
    expect(order, [...order]..sort());
    // The uncovered skill keeps its own folded list.
    expect(find.text('Skills Bousla does not cover yet: 1'), findsOneWidget);
    // Each skill is one row; its evidence opens on a tap.
    expect(find.textContaining('sql_join: May need review'), findsNothing);
    await tester.tap(find.text('Skill gap'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('skill-gap')),
            matching: find.textContaining('sql_join: May need review')),
        findsOneWidget);

    await tester.tap(_essential);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill-shown')), findsNothing);
    expect(content.conceptReads, 1);
  });

  testWidgets('real datasets: no skill lost, no empty group', (tester) async {
    for (final role in _bundledRoles()) {
      await _show(tester, [role]);
      await tester.tap(_essential);
      await tester.pumpAndSettle();
      final report = careerGaps(role, standingsFromSessions(_sessions));
      final essential = report.skills.where((s) => s.skill.essential);
      final covered =
          essential.where((s) => s.status != SkillStatus.outsideBousla);
      // Every covered essential skill: exactly one card, in its group.
      for (final s in covered) {
        expect(
            find.descendant(
                of: find.byKey(ValueKey('skill-group-${s.status.name}')),
                matching: find.byKey(ValueKey('skill-${s.skill.id}'))),
            findsOneWidget,
            reason: '${role.id}/${s.skill.id}');
      }
      // A group is shown only when it has skills.
      for (final st in SkillStatus.values) {
        if (st == SkillStatus.outsideBousla) continue;
        final n = covered.where((s) => s.status == st).length;
        expect(find.byKey(ValueKey('skill-group-${st.name}')),
            n == 0 ? findsNothing : findsOneWidget,
            reason: '${role.id}/${st.name}');
      }
      // The uncovered ones: all in the folded list.
      final outside =
          essential.where((s) => s.status == SkillStatus.outsideBousla);
      if (outside.isNotEmpty) {
        await tester.tap(find
            .text('Skills Bousla does not cover yet: ${outside.length}')
            .first);
        await tester.pumpAndSettle();
        for (final s in outside) {
          expect(
              find.byKey(ValueKey('outside-skill-${s.skill.id}')), findsWidgets,
              reason: s.skill.id);
        }
      }
    }
  });

  testWidgets('each section keeps its own state', (tester) async {
    await _show(tester, _bundledRoles());
    await tester.tap(_essential);
    await tester.pumpAndSettle();
    // Opening the skills does not open the market.
    expect(find.byKey(const ValueKey('skill-query-languages')), findsOneWidget);
    expect(find.byKey(const ValueKey('local-top-database-management-systems')),
        findsNothing);
    await tester.tap(_local);
    await tester.pumpAndSettle();
    await tester.tap(_essential);
    await tester.pumpAndSettle();
    // Closing the skills leaves the market open.
    expect(find.byKey(const ValueKey('skill-query-languages')), findsNothing);
    expect(find.byKey(const ValueKey('local-top-database-management-systems')),
        findsOneWidget);
  });

  testWidgets('Arabic: right to left, same behaviour', (tester) async {
    await _show(tester, [_everyStatusRole()], locale: 'ar');
    final title = find.text('مهارات أساسية');
    expect(title, findsOneWidget);
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
    expect(find.byKey(const ValueKey('skill-shown')), findsNothing);
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(find.text('قد تحتاج مراجعة (1)'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('skill-group-possibleGap')),
            matching: find.byKey(const ValueKey('skill-gap'))),
        findsOneWidget);
  });

  testWidgets('useful skills: a closed card too; a skill opens on a tap',
      (tester) async {
    await _show(tester, _bundledRoles().reversed.toList()); // data analyst
    final useful = find.text('Useful skills');
    expect(useful, findsOneWidget);
    expect(find.byKey(const ValueKey('coverage-optional')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('optional-group-noEvidence')), findsNothing);
    await tester.tap(useful);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('outside-optional')), findsOneWidget);

    // Essential: rows with names only, details after a tap on one row.
    await tester.tap(_essential);
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('skill-query-languages'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.textContaining('sql_join:')),
        findsNothing);
    await tester
        .tap(find.descendant(of: row, matching: find.text('query languages')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: find.textContaining('sql_join:')),
        findsOneWidget);
    // Other skills stay closed.
    expect(find.textContaining('normalization:'), findsNothing);
  });

  testWidgets('local market title is plain; "early sample" inside',
      (tester) async {
    await _show(tester, _bundledRoles());
    expect(find.text('Local job market'), findsOneWidget);
    expect(find.byKey(const ValueKey('career-local-early')), findsNothing);
    await tester.tap(_local);
    await tester.pumpAndSettle();
    expect(find.text('Early sample'), findsOneWidget);
  });
}
