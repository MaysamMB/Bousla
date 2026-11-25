// Resources on the student's feedback screen: title, description, and a
// link that opens (through the shared openLink) only when it is a web link.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/features/student_web/feedback/feedback_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

FeedbackResource _res(
  String id,
  String en, {
  ResourceType type = ResourceType.video,
  String? url,
  LocalizedText? description,
}) =>
    FeedbackResource(
      id: id,
      title: LocalizedText(ar: 'عنوان $id', en: en),
      type: type,
      url: url,
      description: description,
    );

StudentFeedback _feedback(List<FeedbackResource> resources) => StudentFeedback(
      language: Language.en,
      concepts: const [
        FeedbackConcept(
          conceptId: 'primary_key',
          name: LocalizedText(ar: 'المفتاح الأساسي', en: 'Primary Key'),
          state: MasteryState.possibleDifficulty,
          attempts: 2,
          correct: 0,
        ),
      ],
      recommendations: [
        FeedbackRecommendation(
          conceptId: 'primary_key',
          reason: RecommendationReason.reviewConcept,
          resources: resources,
        ),
      ],
    );

Future<List<String>> _show(
  WidgetTester tester,
  List<FeedbackResource> resources, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <String>[];
  await tester.pumpWidget(
    ServicesScope(
      services: AppServices.inMemory(),
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: FeedbackView(
            feedback: _feedback(resources),
            openLink: opened.add,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('title, description and a link that opens with openLink',
      (tester) async {
    final opened = await _show(tester, [
      _res(
        'v',
        'Primary keys explained',
        url: 'https://example.edu/pk',
        description: const LocalizedText(
          ar: 'لماذا يكون المفتاح الأساسي فريدًا',
          en: 'Why a primary key is unique',
        ),
      ),
    ]);
    expect(find.text('Primary keys explained'), findsOneWidget);
    expect(find.text('Why a primary key is unique'), findsOneWidget);
    expect(find.text('https://example.edu/pk'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);

    // The description sits in the same tile as its title.
    final tile = find.ancestor(
      of: find.text('Primary keys explained'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(
          of: tile, matching: find.text('Why a primary key is unique')),
      findsOneWidget,
    );

    await tester.tap(find.text('Primary keys explained'));
    await tester.pumpAndSettle();
    expect(opened, ['https://example.edu/pk']);
  });

  testWidgets('Arabic: the Arabic description, the link stays LTR',
      (tester) async {
    final opened = await _show(
      tester,
      [
        _res(
          'v',
          'Primary keys explained',
          url: 'https://example.edu/pk',
          description: const LocalizedText(
            ar: 'لماذا يكون المفتاح الأساسي فريدًا',
            en: 'Why a primary key is unique',
          ),
        ),
      ],
      locale: 'ar',
    );
    expect(find.text('عنوان v'), findsOneWidget);
    expect(find.text('لماذا يكون المفتاح الأساسي فريدًا'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('https://example.edu/pk'))),
      TextDirection.ltr,
    );
    await tester.tap(find.text('عنوان v'));
    expect(opened, ['https://example.edu/pk']);
  });

  testWidgets('no description: nothing empty or "null" is shown',
      (tester) async {
    await _show(tester, [
      _res('a', 'No description', url: 'https://example.edu/a'),
      _res(
        'b',
        'Blank description',
        url: 'https://example.edu/b',
        description: const LocalizedText(ar: ' ', en: ''),
      ),
    ]);
    expect(find.text('No description'), findsOneWidget);
    expect(find.text('Blank description'), findsOneWidget);
    expect(find.textContaining('null'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a description only in the other language is still shown',
      (tester) async {
    await _show(tester, [
      _res(
        'a',
        'Activity',
        type: ResourceType.activity,
        description: const LocalizedText(ar: 'صمّم جدولين واربطهما', en: ''),
      ),
    ]);
    expect(find.text('صمّم جدولين واربطهما'), findsOneWidget);
  });

  testWidgets('no link: nothing clickable; an activity says so',
      (tester) async {
    final opened = await _show(tester, [
      _res('act', 'Design two tables', type: ResourceType.activity),
    ]);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    final tile = tester.widget<ListTile>(find.ancestor(
      of: find.text('Design two tables'),
      matching: find.byType(ListTile),
    ));
    expect(tile.onTap, isNull);
    await tester.tap(find.text('Design two tables'));
    expect(opened, isEmpty);
  });

  testWidgets('malformed or unsafe links are neither shown nor opened',
      (tester) async {
    final opened = await _show(tester, [
      _res('x', 'Script link', url: 'javascript:alert(1)'),
      _res('y', 'Not a link', url: 'pk tutorial'),
      _res('z', 'Blank link', url: '   '),
    ]);
    expect(find.textContaining('javascript'), findsNothing);
    expect(find.text('pk tutorial'), findsNothing);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    for (final t in ['Script link', 'Not a link', 'Blank link']) {
      await tester.tap(find.text(t));
    }
    expect(opened, isEmpty);
  });
}
