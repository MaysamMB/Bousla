import 'dart:async';

import 'package:bousla_app/features/instructor/sessions/teaching_actions.dart';
import 'package:bousla_app/features/instructor/sessions/teaching_strategy.dart';
import 'package:bousla_app/features/instructor/sessions/teaching_strategy_panel.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app({TeachingStrategyChooser? choose, String locale = 'en',
    Key? snapshotKey}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: SingleChildScrollView(child: TeachingStrategyPanel(
    key: snapshotKey,
    action: const TeachingAction(conceptId: 'pk',
      kind: TeachingActionKind.reviewConcept, affectedCount: 6, groupCount: 8),
    conceptName: locale == 'ar' ? 'المفتاح الأساسي' : 'Primary Key',
    choose: choose,
  ))),
);

void main() {
  testWidgets('no automatic request; one tap selects a tactic', (tester) async {
    var calls = 0;
    await tester.pumpWidget(app(choose: (_) async {
      calls++;
      return '{"strategy":"peerExplanation","example":"Compare a primary key with a foreign key.","question":"Which key references another table?"}';
    }));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Ask Gemini to select a tactic'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('AI-selected tactic'), findsOneWidget);
    expect(find.text('Draft teaching example'), findsOneWidget);
    expect(find.text('Unreviewed AI draft — verify before classroom use.'), findsOneWidget);
    expect(find.text('Ask Gemini to select a tactic'), findsNothing);
  });
  testWidgets('offline Arabic is RTL and has no network button', (tester) async {
    await tester.pumpWidget(app(locale: 'ar'));
    await tester.pumpAndSettle();
    final label = find.text('استراتيجية من القواعد الثابتة');
    expect(label, findsOneWidget);
    expect(Directionality.of(tester.element(label)), TextDirection.rtl);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('invalid answer keeps rule label', (tester) async {
    await tester.pumpWidget(app(choose: (_) async => '{"strategy":"bad"}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask Gemini to select a tactic'));
    await tester.pumpAndSettle();
    expect(find.text('Rule-based tactic'), findsOneWidget);
    expect(find.text('AI-selected tactic'), findsNothing);
  });
  testWidgets('late result is ignored after evidence snapshot changes', (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(app(snapshotKey: const ValueKey(1),
      choose: (_) => pending.future));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask Gemini to select a tactic'));
    await tester.pump();
    await tester.pumpWidget(app(snapshotKey: const ValueKey(2)));
    pending.complete('{"strategy":"peerExplanation","example":"Compare a primary key with a foreign key.","question":"Which key references another table?"}');
    await tester.pumpAndSettle();
    expect(find.text('AI-selected tactic'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
