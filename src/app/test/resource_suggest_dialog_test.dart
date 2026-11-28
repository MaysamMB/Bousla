// The "Suggest resources (AI)" dialog: the instructor's own description,
// the latest session's results when there is none, duplicates, and AI
// failure. No real Gemini call: a fake suggester answers.
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/ai/resource_suggester.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/resources/resources_screen.dart';
import 'package:bousla_app/features/instructor/resources/session_focus.dart';
import 'package:bousla_app/features/instructor/resources/suggest_resources_dialog.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'database_systems';

ResourceSuggestion _suggestion(String en, {String ar = 'فيديو عن المفتاح'}) =>
    ResourceSuggestion(
      conceptIds: const ['foreign_key'],
      kind: SuggestedKind.video,
      language: ResourceLanguage.both,
      title: LocalizedText(ar: ar, en: en),
      description: const LocalizedText(ar: 'يشرح الربط', en: 'Explains links'),
      whereToFind: const LocalizedText(ar: 'يوتيوب', en: 'YouTube'),
    );

class _FakeSuggester implements ResourceSuggester {
  _FakeSuggester({this.answer = const [], this.error});

  final List<ResourceSuggestion> answer;
  final Object? error;
  var calls = 0;
  List<Concept>? concepts;
  String? request;
  ClassResourceFocus? focus;
  Map<String, List<String>>? questions;

  @override
  String get modelName => 'fake-model';

  @override
  Future<SuggestionParseResult> suggestResources({
    required List<Concept> concepts,
    int perConcept = 2,
    MaterialFile? material,
    String? request,
    ClassResourceFocus? focus,
    Map<String, List<String>> questionsByConcept = const {},
    bool searchWeb = true,
  }) async {
    calls++;
    this.concepts = concepts;
    this.request = request;
    this.focus = focus;
    questions = questionsByConcept;
    if (error != null) throw error!;
    return SuggestionParseResult(accepted: answer, dropped: const []);
  }
}

/// Foreign Key was hard in the latest session, with Primary Key as a
/// possible foundation gap.
SessionFocus _focus() => SessionFocus(
      session: Session(
        id: 'S1',
        code: 'S1',
        courseId: _course,
        ownerId: 'teacher',
        questions: const [],
        status: SessionStatus.closed,
        feedbackReleased: true,
        title: const LocalizedText(ar: 'جلسة المفاتيح', en: 'Keys quiz'),
      ),
      focus: const ClassResourceFocus(
        difficultConceptIds: ['foreign_key'],
        prerequisiteGaps: [('foreign_key', 'primary_key')],
      ),
    );

Future<(AppServices, List<String?>)> _open(
  WidgetTester tester,
  _FakeSuggester ai, {
  SessionFocus? focus,
}) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices(
    content: InMemoryContentRepository(),
    sessions: InMemorySessionRepository(),
    inMemory: true,
    resourceSuggester: ai,
    initialLocale: const Locale('en'),
  );
  final concepts = [
    for (final c in await services.content.listConcepts(_course))
      if (c.status == ReviewStatus.approved) c,
  ];
  final popped = <String?>[];
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => popped.add(
                  await showDialog<String>(
                    context: context,
                    builder: (_) => SuggestResourcesDialog(
                      courseId: _course,
                      concepts: concepts,
                      loadFocus: () async => focus,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (services, popped);
}

/// pumpAndSettle never settles while a text field has the blinking cursor.
Future<void> _unfocusAndSettle(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

bool _chipSelected(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

void main() {
  testWidgets('with a description: it is sent, the session focus is not',
      (tester) async {
    final ai = _FakeSuggester(answer: [_suggestion('Joins between tables')]);
    final (services, popped) = await _open(tester, ai, focus: _focus());
    await tester.enterText(
      find.byType(TextField),
      'Short videos for students who mix up primary and foreign keys',
    );
    await _unfocusAndSettle(tester);
    // The session note is only shown while nothing is written.
    expect(find.byKey(const ValueKey('resource-focus')), findsNothing);
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    expect(ai.calls, 1);
    expect(ai.request,
        'Short videos for students who mix up primary and foreign keys');
    expect(ai.focus, isNull);
    expect(popped.single, contains('1 suggestions saved for review'));
    final saved =
        await services.content.listResources(_course, approvedOnly: false);
    // Saved as a pending AI suggestion, without a link: not for students.
    final s = saved.firstWhere((r) => r.title.en == 'Joins between tables');
    expect(s.status, ReviewStatus.pendingReview);
    expect(s.url, isNull);
  });

  testWidgets('without a description: the latest session guides it',
      (tester) async {
    final ai = _FakeSuggester(answer: [_suggestion('Foreign keys, slowly')]);
    await _open(tester, ai, focus: _focus());
    expect(
      find.text('Without a description, the suggestions follow the results '
          'of “Keys quiz”: Primary Key, Foreign Key. These concepts are '
          'chosen below; you can change them.'),
      findsOneWidget,
    );
    // The session's concepts are chosen, the others not.
    expect(_chipSelected(tester, 'Foreign Key'), isTrue);
    expect(_chipSelected(tester, 'Primary Key'), isTrue);
    expect(_chipSelected(tester, 'Relational Model'), isFalse);

    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(ai.request, isNull);
    expect(ai.focus!.difficultConceptIds, ['foreign_key']);
    expect(
        ai.concepts!.map((c) => c.id).toSet(), {'primary_key', 'foreign_key'});
  });

  testWidgets('no session results: says so, all concepts stay chosen',
      (tester) async {
    final ai = _FakeSuggester(answer: [_suggestion('Something new')]);
    await _open(tester, ai);
    expect(find.textContaining('No session results to guide'), findsOneWidget);
    expect(_chipSelected(tester, 'Relational Model'), isTrue);
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(ai.focus, isNull);
    expect(ai.request, isNull);
  });

  testWidgets('a suggestion the course already has is not added again',
      (tester) async {
    // The sample course has "Practice: Primary Key".
    final ai = _FakeSuggester(answer: [
      _suggestion('Practice: Primary Key', ar: 'تدريب: المفتاح الأساسي'),
      _suggestion('A brand new video'),
    ]);
    final (services, popped) = await _open(tester, ai);
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(popped.single, contains('1 suggestions saved for review'));
    expect(popped.single,
        contains('1 skipped: the course already has a resource'));
    final all =
        await services.content.listResources(_course, approvedOnly: false);
    expect(
        all.where((r) => r.title.en == 'Practice: Primary Key'), hasLength(1));
  });

  testWidgets('only duplicates: nothing saved, the dialog says why',
      (tester) async {
    final ai = _FakeSuggester(answer: [
      _suggestion('Practice: Primary Key', ar: 'تدريب: المفتاح الأساسي'),
    ]);
    final (services, popped) = await _open(tester, ai);
    final before =
        (await services.content.listResources(_course, approvedOnly: false))
            .length;
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(popped, isEmpty, reason: 'the dialog stays open');
    expect(find.textContaining('Every suggestion matches a resource'),
        findsOneWidget);
    expect(
      (await services.content.listResources(_course, approvedOnly: false))
          .length,
      before,
    );
  });

  testWidgets('AI fails: an error, nothing saved, manual adding still works',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ai = _FakeSuggester(
      error: const QuestionGenerationException(GenerationProblem.busy),
    );
    final services = AppServices(
      content: InMemoryContentRepository(),
      sessions: InMemorySessionRepository(),
      inMemory: true,
      resourceSuggester: ai,
      initialLocale: const Locale('en'),
    );
    await tester.pumpWidget(ServicesScope(
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
    ));
    await tester.pumpAndSettle();
    // The existing catalog is listed.
    expect(find.text('Practice: Primary Key'), findsOneWidget);
    final before =
        (await services.content.listResources(_course, approvedOnly: false))
            .length;

    await tester.tap(find.text('Suggest resources (AI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();
    expect(ai.calls, 1);
    expect(find.textContaining('busy'), findsOneWidget);
    expect(
      (await services.content.listResources(_course, approvedOnly: false))
          .length,
      before,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Add resource'), findsOneWidget);
  });

  testWidgets(
      'web search: question prompts give the context; a found link is kept for approval',
      (tester) async {
    const found = ResourceSuggestion(
      conceptIds: ['foreign_key'],
      kind: SuggestedKind.video,
      language: ResourceLanguage.en,
      title: LocalizedText(
          ar: 'المفتاح الخارجي باختصار', en: 'Foreign keys, briefly'),
      description: LocalizedText(ar: 'فيديو قصير', en: 'A short video'),
      whereToFind: LocalizedText(ar: 'يوتيوب', en: 'YouTube'),
      url: 'https://www.youtube.com/watch?v=fk',
      minutes: 6,
    );
    final ai = _FakeSuggester(answer: [found]);
    final (services, _) = await _open(tester, ai, focus: _focus());
    await tester.tap(find.text('Suggest'));
    await tester.pumpAndSettle();

    // Prompts of approved questions on the chosen concepts, no answers.
    expect(ai.questions!.keys, isNotEmpty);
    expect(
        ai.questions!.keys.toSet().difference({'primary_key', 'foreign_key'}),
        isEmpty);
    final saved =
        (await services.content.listResources(_course, approvedOnly: false))
            .firstWhere((r) => r.title.en == 'Foreign keys, briefly');
    expect(saved.url, 'https://www.youtube.com/watch?v=fk');
    // Still waiting for the instructor.
    expect(saved.status, ReviewStatus.pendingReview);
    expect(saved.whereToFind!.en, contains('about 6 min (estimate)'));
  });
}
