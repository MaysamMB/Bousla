// What the "Publish feedback" dialog tells the instructor after publishing:
// the guard count comes from the five guards' real results (not a fixed
// number), Gemini failure is reported, and template text is never counted
// as AI. The model is a fake here: this tests the dialog, not Gemini (see
// src/engine/tool/gemini_explanation_eval.dart for the real-Gemini run).
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/ai/feedback_explainer.dart';
import 'package:bousla_app/data/ai/question_generator.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/feedback.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/sessions/publish_feedback_dialog.dart';
import 'package:bousla_app/l10n/app_localizations.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _okAr = 'شكرًا لمشاركتك في الجلسة. الخطوات التالية قد تساعدك.';
const _okEn = 'Thank you for taking part. The next steps may help you.';

/// Answers one request; [bad] profiles (by index) get text that breaks a
/// guard (forbidden wording).
class _Explainer implements FeedbackExplainer {
  _Explainer({this.bad = const {}, this.error});

  final Set<int> bad;
  final Object? error;
  var calls = 0;

  @override
  Future<ExplainerAnswer> explain(List<ExplanationProfile> profiles) async {
    calls++;
    if (error != null) throw error!;
    final entries = [
      for (var i = 0; i < profiles.length; i++)
        '{"profile_id": "${profiles[i].id}", '
            '"text_ar": "${bad.contains(i) ? 'لديك فجوة.' : _okAr}", '
            '"text_en": "${bad.contains(i) ? 'You have a gap.' : _okEn}"}',
    ];
    return ExplainerAnswer(text: '[${entries.join(',')}]', model: 'fake');
  }
}

/// A closed session where 3 students answered differently (3 profiles).
Future<(AppServices, Session)> _session(_Explainer explainer) async {
  final content = InMemoryContentRepository();
  final sessions = InMemorySessionRepository();
  final services = AppServices(
    content: content,
    sessions: sessions,
    feedbackExplainer: explainer,
    initialLocale: const Locale('en'),
  );
  final questions = await content.listQuestions('database_systems');
  final keys = await content.answerKeys('database_systems');
  final session = await sessions.createSession(
    courseId: 'database_systems',
    ownerId: 'teacher',
    questions: [for (final q in questions) QuestionRef(q.id, q.version)],
  );
  for (var s = 0; s < 3; s++) {
    for (var n = 0; n < questions.length; n++) {
      final q = questions[n];
      final right =
          keys.firstWhere((k) => k.questionId == q.id).correctOptionId;
      // Student s answers the first s questions right, the rest wrong.
      final pick =
          n < s * 2 ? right : q.options.firstWhere((o) => o.id != right).id;
      await sessions.submitResponse(
        session.id,
        Response(
          participantId: 'student$s',
          questionId: q.id,
          questionVersion: q.version,
          selectedOptionId: pick,
          displayLanguage: Language.en,
        ),
      );
    }
  }
  await sessions.closeSession(session.id);
  return (services, session);
}

Future<void> _publish(
  WidgetTester tester,
  AppServices services,
  Session session,
) async {
  await tester.pumpWidget(ServicesScope(
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
      home: Scaffold(body: PublishFeedbackDialog(session: session)),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Publish'));
  // Publishing awaits in-memory streams that finish on the real event loop.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<List<FeedbackExplanation>> _saved(
        AppServices s, Session session) async =>
    [
      for (final p in ['student0', 'student1', 'student2'])
        (await s.sessions.watchMyFeedback(session.id, p).first)!.explanation!,
    ];

void main() {
  testWidgets(
      'one explanation fails a guard: the dialog says 1, from the '
      'guards', (tester) async {
    final explainer = _Explainer(bad: {0});
    final (services, session) = await _session(explainer);
    await _publish(tester, services, session);

    expect(explainer.calls, 1, reason: 'one request for the whole class');
    expect(find.text('Feedback published for 3 students.'), findsOneWidget);
    expect(
      find.text('AI explanation: 2 students · template: 1 students · '
          '3 different result profiles'),
      findsOneWidget,
    );
    expect(
      find.text('1 AI explanations failed the safety checks and were '
          'replaced by the template.'),
      findsOneWidget,
    );
    expect(find.textContaining('Gemini was not available'), findsNothing);

    final saved = await _saved(services, session);
    // The rejected text never reaches a student; its replacement is the
    // template, saved as template (no AI label, no model).
    expect(saved.where((e) => e.source == ExplanationSource.ai), hasLength(2));
    final template =
        saved.singleWhere((e) => e.source == ExplanationSource.template);
    expect(template.model, isNull);
    expect(template.text.en, isNot(contains('gap')));
  });

  testWidgets('all pass: no guard message', (tester) async {
    final (services, session) = await _session(_Explainer());
    await _publish(tester, services, session);
    expect(find.textContaining('failed the safety checks'), findsNothing);
    expect(
      find.text('AI explanation: 3 students · template: 0 students · '
          '3 different result profiles'),
      findsOneWidget,
    );
  });

  testWidgets('Gemini unavailable: said so, no guard count, all template',
      (tester) async {
    final explainer = _Explainer(
      error: const QuestionGenerationException(GenerationProblem.dailyQuota),
    );
    final (services, session) = await _session(explainer);
    await _publish(tester, services, session);
    expect(
      find.text('Gemini was not available, so the fixed template was used '
          'for everyone.'),
      findsOneWidget,
    );
    expect(find.textContaining('failed the safety checks'), findsNothing);
    final saved = await _saved(services, session);
    expect(saved.every((e) => e.source == ExplanationSource.template), isTrue);
    expect(saved.every((e) => e.model == null), isTrue);
  });
}
