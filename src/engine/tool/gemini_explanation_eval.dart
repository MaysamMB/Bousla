// Real-Gemini evaluation of AI level 2 explanations (docs/architecture.md
// §9, "report the real guard pass rate").
//
// The same 20 profiles as the mocked guard test (test/support/
// explanation_eval_cases.dart) are sent in ONE request, with the app's own
// prompt and JSON schema (buildFeedbackExplanationPrompt,
// feedbackExplanationJsonSchema), to the app's models, and the real answer
// goes through the app's five guards (resolveExplanations), unchanged.
// Nothing here is mocked: no answer, no fixture, no fallback text counted
// as AI.
//
// Run from src/engine, with a Gemini API key (Google AI Studio):
//
//   GEMINI_API_KEY=... dart run tool/gemini_explanation_eval.dart --out <dir>
//
// Without GEMINI_API_KEY no key header is sent (an environment network
// secret may add it). If no model answers (key, quota, network), every case
// is an EXECUTION FAILURE: not accepted, not rejected, and no rate is given.
//
// Options: --model (default gemini-3.8-flash), --fallback-model (default
// gemini-3.5-flash-lite, the app's fallback; empty to skip), --out <dir> for
// the report (report.md, report.json, model_answer.json).
// This tool makes network calls, so it is NOT in lib/ (the engine library
// itself stays network-free).
import 'dart:convert';
import 'dart:io';

import 'package:bousla_engine/bousla_engine.dart';

import '../test/support/explanation_eval_cases.dart';

const _endpoint = 'https://generativelanguage.googleapis.com/v1beta/models';

/// The guard (1–5) behind an issue, or null for issues that are not guards.
int? guardNumber(ExplanationIssue i) => switch (i) {
      ExplanationIssue.unknownConcept => 1,
      ExplanationIssue.unapprovedResource => 2,
      ExplanationIssue.wrongLanguage => 3,
      ExplanationIssue.forbiddenWording => 4,
      ExplanationIssue.tooLong => 5,
      ExplanationIssue.invalidAnswer || ExplanationIssue.missing => null,
    };

class _Call {
  _Call({required this.model, this.text, this.status, this.error});

  final String model;
  final String? text;
  final int? status;
  final String? error;
  bool get ok => text != null;
}

/// One generateContent request. Never retried here more than the app does:
/// one attempt per model.
Future<_Call> _generate(String model, String prompt, String? key) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client
        .postUrl(Uri.parse('$_endpoint/$model:generateContent'))
        .timeout(const Duration(seconds: 30));
    req.headers.contentType = ContentType.json;
    if (key != null && key.isNotEmpty) req.headers.set('x-goog-api-key', key);
    req.write(jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseJsonSchema': feedbackExplanationJsonSchema(),
        'temperature': 0.3,
      },
    }));
    final res = await req.close().timeout(const Duration(seconds: 180));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      return _Call(
        model: model,
        status: res.statusCode,
        error: body.length > 600 ? '${body.substring(0, 600)}…' : body,
      );
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List? ?? const [];
    final parts = candidates.isEmpty
        ? const []
        : ((candidates.first as Map)['content'] as Map?)?['parts'] as List? ??
            const [];
    final text = [
      for (final p in parts)
        if (p is Map && p['text'] is String) p['text'] as String,
    ].join();
    if (text.trim().isEmpty) {
      return _Call(
        model: model,
        status: 200,
        error: 'empty answer (finish: '
            '${candidates.isEmpty ? 'no candidates' : (candidates.first as Map)['finishReason']})',
      );
    }
    return _Call(model: model, status: 200, text: text);
  } on Object catch (e) {
    return _Call(model: model, error: e.toString());
  } finally {
    client.close(force: true);
  }
}

String? _arg(List<String> args, String name, String? fallback) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}

Future<void> main(List<String> args) async {
  final model = _arg(args, '--model', 'gemini-3.8-flash')!;
  final fallback = _arg(args, '--fallback-model', 'gemini-3.5-flash-lite')!;
  final out = Directory(_arg(args, '--out', 'gemini_eval_report')!)
    ..createSync(recursive: true);
  final key = Platform.environment['GEMINI_API_KEY'];

  // The app's pipeline: 26 students → 20 unique anonymous profiles.
  final (responses, patternOf) = evalStudents();
  final groups = groupProfiles(evalProfiles(responses));
  final profileOfPattern = {
    for (final e in patternOf.entries) e.value: groups.profileOf(e.key),
  };
  final prompt = buildFeedbackExplanationPrompt(groups.profiles);
  for (final s in patternOf.keys) {
    if (prompt.contains(s)) throw StateError('student ID in the prompt');
  }

  // ONE request for the whole class; the fallback model only if the first
  // one gave no answer (as in the app).
  final calls = <_Call>[await _generate(model, prompt, key)];
  if (!calls.last.ok && fallback.isNotEmpty) {
    calls.add(await _generate(fallback, prompt, key));
  }
  final answered = calls.where((c) => c.ok).firstOrNull;
  final now = DateTime.now().toUtc().toIso8601String();
  final callLines = [
    for (final c in calls)
      '- `${c.model}`: ${c.ok ? 'answered (HTTP 200)' : 'no answer (${c.status == null ? 'no HTTP response' : 'HTTP ${c.status}'}): ${c.error?.replaceAll('\n', ' ')}'}',
  ];

  final rows = <Map<String, Object?>>[];
  final md = StringBuffer()
    ..writeln('# AI level 2 — real Gemini evaluation')
    ..writeln()
    ..writeln('Run: $now. Cases: ${evalPatterns.length} profiles '
        '(${patternOf.length} students), one request.')
    ..writeln()
    ..writeln('Requests:')
    ..writeAll(callLines.map((l) => '$l\n'))
    ..writeln();

  if (answered == null) {
    for (var i = 0; i < evalPatterns.length; i++) {
      rows.add({
        'case': i + 1,
        'pattern': evalPatterns[i].$1,
        'request_completed': false,
        'result': 'execution_failure',
        'reason': calls.last.error,
      });
    }
    md
      ..writeln('**No model answered: all ${evalPatterns.length} cases are '
          'execution failures.** Nothing was accepted or rejected, and no '
          'success rate can be computed.')
      ..writeln()
      ..writeln('The app would publish the template explanation for every '
          'student in this situation.');
  } else {
    File('${out.path}/model_answer.json').writeAsStringSync(answered.text!);
    final batch = resolveExplanations(
      profiles: groups.profiles,
      modelAnswer: answered.text,
      courseConcepts: evalCourse,
      courseResources: evalResources,
    );
    md
      ..writeln('Model that answered: `${answered.model}`.')
      ..writeln()
      ..writeln('| # | Profile | Request | Result | Guard(s) / reason | '
          'Fallback used |')
      ..writeln('|---|---|---|---|---|---|');
    var accepted = 0;
    for (var i = 0; i < evalPatterns.length; i++) {
      final o = batch.byProfile[profileOfPattern[i]!.id]!;
      if (o.fromAi) accepted++;
      final guards = {
        for (final issue in o.issues)
          if (guardNumber(issue) case final g?) g,
      }.toList()
        ..sort();
      final reason = o.fromAi
          ? ''
          : [
              if (guards.isNotEmpty) 'guard ${guards.join(', ')}',
              ...o.issues.map((x) => x.name),
            ].join(': ');
      rows.add({
        'case': i + 1,
        'pattern': evalPatterns[i].$1,
        'profile_id': profileOfPattern[i]!.id,
        'request_completed': true,
        'result': o.fromAi ? 'accepted' : 'rejected',
        'guards': guards,
        'issues': [for (final x in o.issues) x.name],
        'fallback_used': !o.fromAi,
        'text_ar': o.text.ar,
        'text_en': o.text.en,
      });
      md.writeln('| ${i + 1} | ${evalPatterns[i].$1} | completed | '
          '${o.fromAi ? 'accepted' : 'rejected'} | $reason | '
          '${o.fromAi ? 'no' : 'yes (template)'} |');
    }
    final evaluated = evalPatterns.length;
    final rate = 100 * accepted / evaluated;
    md
      ..writeln()
      ..writeln('**Real Gemini success rate: $accepted of $evaluated '
          '(${rate.toStringAsFixed(1)}%)** passed all five guards; '
          '${evaluated - accepted} used the template explanation.')
      ..writeln()
      ..writeln(
          'Rejections per issue: ${batch.issueCounts.isEmpty ? 'none' : batch.issueCounts.entries.map((e) => '${e.key.name} ${e.value}').join(', ')}.');
  }

  File('${out.path}/report.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'run_at': now,
      'requests': [
        for (final c in calls)
          {'model': c.model, 'ok': c.ok, 'status': c.status, 'error': c.error},
      ],
      'cases': rows,
    }),
  );
  File('${out.path}/report.md').writeAsStringSync(md.toString());
  stdout.write(md.toString());
  if (answered == null) exitCode = 2;
}
