import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/ai/resource_suggester.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/features/instructor/resources/resources_screen.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSuggester implements ResourceSuggester {
  List<Concept>? asked;

  @override
  String get modelName => 'fake-model';

  @override
  Future<SuggestionParseResult> suggestResources({
    required List<Concept> concepts,
    int perConcept = 2,
    MaterialFile? material,
  }) async {
    asked = concepts;
    return const SuggestionParseResult(
      accepted: [
        ResourceSuggestion(
          conceptIds: ['foreign_key'],
          kind: SuggestedKind.video,
          language: ResourceLanguage.en,
          title: LocalizedText(
            ar: 'فيديو عن المفتاح الخارجي',
            en: 'Foreign key video',
          ),
          description: LocalizedText(
            ar: 'يشرح كيف يربط المفتاح الخارجي جدولين.',
            en: 'Shows how a foreign key links two tables.',
          ),
          whereToFind: LocalizedText(
            ar: 'يوتيوب، قناة جامعية',
            en: 'YouTube, a university channel',
          ),
          searchQuery: 'foreign key database tutorial',
        ),
      ],
      dropped: [SuggestionIssue.containsLink],
    );
  }
}

Future<AppServices> _show(WidgetTester tester, {_FakeSuggester? ai}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices(
    content: InMemoryContentRepository(),
    sessions: InMemorySessionRepository(),
    inMemory: true,
    resourceSuggester: ai,
    initialLocale: const Locale('en'),
  );
  await tester.pumpWidget(
    ServicesScope(
      services: services,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ResourcesScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

/// Lets the dialog's save finish without pumpAndSettle (a focused text
/// field's cursor never settles).
Future<void> _settleSave(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the instructor adds a resource with one title', (tester) async {
    final services = await _show(tester);
    expect(find.text('Suggest resources (AI)'), findsNothing);
    await tester.tap(find.text('Add resource'));
    await tester.pumpAndSettle();

    // Without a link, a video is refused.
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'شرح المفتاح الخارجي',
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Foreign Key'));
    await tester.pump();
    await tester.tap(find.text('Save and approve'));
    await _settleSave(tester);
    expect(find.text('Add the link to the resource.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'https://example.edu/fk',
    );
    await tester.tap(find.text('Save and approve'));
    await _settleSave(tester);
    await tester.pumpAndSettle();

    expect(find.text('Resource saved and approved.'), findsOneWidget);
    expect(find.text('شرح المفتاح الخارجي'), findsOneWidget);
    final saved = (await services.content.listResources('database_systems'))
        .where((r) => r.url == 'https://example.edu/fk')
        .single;
    // Arabic title → Arabic resource, chosen automatically.
    expect(saved.language, ResourceLanguage.ar);
    expect(saved.conceptIds, ['foreign_key']);
  });

  testWidgets('AI describes a resource; the instructor adds the link',
      (tester) async {
    final ai = _FakeSuggester();
    final services = await _show(tester, ai: ai);
    await tester.tap(find.text('Suggest resources (AI)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It gives no links'), findsOneWidget);
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    expect(ai.asked, isNotEmpty);
    expect(find.textContaining('1 suggestions saved for review'),
        findsOneWidget);
    expect(find.textContaining('1 because they contained links'),
        findsOneWidget);
    expect(find.text('AI suggestions waiting for a link (1)'), findsOneWidget);
    expect(find.text('Where to look: YouTube, a university channel'),
        findsOneWidget);
    expect(find.text('foreign key database tutorial'), findsOneWidget);
    // Not given to students yet.
    expect(
      (await services.content.listResources('database_systems'))
          .where((r) => r.source == 'ai_draft' && r.url == null),
      isEmpty,
    );

    await tester.tap(find.text('Add link and approve'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Link'),
      'https://example.edu/fk-video',
    );
    await tester.tap(find.text('Save and approve'));
    await _settleSave(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('waiting for a link'), findsNothing);
    final done = (await services.content.listResources('database_systems'))
        .where((r) => r.url == 'https://example.edu/fk-video')
        .single;
    expect(done.source, 'ai_draft');
    expect(done.title.ar, 'فيديو عن المفتاح الخارجي');
    expect(find.textContaining('suggested by AI'), findsWidgets);
  });
}
