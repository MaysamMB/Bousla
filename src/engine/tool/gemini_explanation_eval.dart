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
// Two ways to reach the same Gemini models, run from src/engine:
//
// 1. Like the app, through Firebase AI Logic, with the project's
//    firebase.env.json (FIREBASE_PROJECT_ID, FIREBASE_API_KEY,
//    FIREBASE_APP_ID); the same endpoint, key header and app ID header as
//    package:firebase_ai. If App Check is enforced for AI Logic (it is on
//    bousla-educathon), Google refuses requests from outside the browser
//    app unless an App Check DEBUG token is given: create one in the
//    Firebase console (App Check → Apps → the web app → Manage debug
//    tokens), put it alone in a file, and pass that file. It is exchanged
//    for a short-lived App Check token (Firebase's official route for
//    trusted test environments); without it, the refusal is reported as an
//    execution failure.
//
//      dart run tool/gemini_explanation_eval.dart \
//        --firebase-env ../app/firebase.env.json \
//        --appcheck-debug-token-file <file> --out <dir>
//
// 2. With a Gemini Developer API key (Google AI Studio), from the
//    environment or from a file holding only the key:
//
//      GEMINI_API_KEY=... dart run tool/gemini_explanation_eval.dart --out <dir>
//      dart run tool/gemini_explanation_eval.dart --gemini-key-file <file> \
//        --out <dir>
//
// Keys and settings are read, never printed, logged or written to the
// report (error messages are scrubbed of the key). Without either, no key
// header is sent (an environment network secret may add it). If no model answers (key, quota, network), every case
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

const _developerApi = 'https://generativelanguage.googleapis.com/v1beta/models';

/// Where requests go and how they are authenticated. Never printed.
class _Target {
  _Target({
    required this.base,
    required this.via,
    this.key,
    this.appId,
    this.secrets = const [],
  });

  /// `<base>/<model>:generateContent`.
  final String base;

  /// Shown in the report: which route was used (no secret).
  final String via;
  final String? key;
  final String? appId;

  /// Short-lived App Check token (from a debug token), when given.
  String? appCheckToken;

  /// Other secret values that must never be written (e.g. a debug token).
  final List<String> secrets;

  String scrub(String text) {
    var out = text;
    for (final s in [key, appCheckToken, ...secrets]) {
      if (s != null && s.isNotEmpty) out = out.replaceAll(s, '<secret>');
    }
    return out;
  }
}

/// A text file as saved on Windows too: UTF-8 with or without a byte order
/// mark, or UTF-16 (what Windows PowerShell 5.1 writes with `>` or
/// Out-File). Read as plain UTF-8, such a file would give a wrong token.
String _readText(String path) {
  final b = File(path).readAsBytesSync();
  String utf16(int start, bool littleEndian) {
    final units = <int>[
      for (var i = start; i + 1 < b.length; i += 2)
        littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1],
    ];
    return String.fromCharCodes(units);
  }

  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return utf16(2, true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return utf16(2, false);
  final start =
      b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF ? 3 : 0;
  return utf8.decode(b.sublist(start));
}

/// A secret kept alone in a file (trimmed). Never printed.
String _readSecretFile(String path, String what) {
  final v = _readText(path).trim();
  if (v.isEmpty) throw FormatException('$what file is empty');
  return v;
}

/// Exchanges an App Check debug token for an App Check token (Firebase's
/// route for trusted test environments). Returns null and an error text
/// (scrubbed) when Firebase refuses it.
Future<(String?, String?)> _exchangeDebugToken(
  _Target t,
  String project,
  String debugToken,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client.postUrl(Uri.parse(
      'https://firebaseappcheck.googleapis.com/v1/projects/$project/apps/'
      '${t.appId}:exchangeDebugToken',
    ));
    req.headers.contentType = ContentType.json;
    req.headers.set('x-goog-api-key', t.key!);
    req.write(jsonEncode({'debugToken': debugToken}));
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      return (null, t.scrub('HTTP ${res.statusCode}: $body'));
    }
    final token = (jsonDecode(body) as Map)['token'];
    return token is String && token.isNotEmpty
        ? (token, null)
        : (null, 'no token in the answer');
  } on Object catch (e) {
    return (null, t.scrub(e.toString()));
  } finally {
    client.close(force: true);
  }
}

/// The app's route (package:firebase_ai, Google AI backend): Firebase AI
/// Logic with the project's web API key.
_Target _firebaseTarget(String path, {String? debugToken}) {
  final json = jsonDecode(_readText(path)) as Map;
  String need(String name) {
    final v = json[name];
    if (v is! String || v.trim().isEmpty) {
      throw FormatException('$name is missing in $path');
    }
    return v.trim();
  }

  final project = need('FIREBASE_PROJECT_ID');
  return _Target(
    base: 'https://firebasevertexai.googleapis.com/v1beta/projects/'
        '$project/models',
    via: 'Firebase AI Logic (project $project), as in the app',
    key: need('FIREBASE_API_KEY'),
    appId: need('FIREBASE_APP_ID'),
    secrets: [if (debugToken != null) debugToken],
  );
}

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
Future<_Call> _generate(String model, String prompt, _Target t) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final req = await client
        .postUrl(Uri.parse('${t.base}/$model:generateContent'))
        .timeout(const Duration(seconds: 30));
    req.headers.contentType = ContentType.json;
    final key = t.key;
    if (key != null && key.isNotEmpty) req.headers.set('x-goog-api-key', key);
    if (t.appId case final id? when id.isNotEmpty) {
      req.headers.set('X-Firebase-AppId', id);
    }
    if (t.appCheckToken case final token? when token.isNotEmpty) {
      req.headers.set('X-Firebase-AppCheck', token);
    }
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
        error: t.scrub(body.length > 600 ? '${body.substring(0, 600)}…' : body),
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
    return _Call(model: model, error: t.scrub(e.toString()));
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
  final firebaseEnv = _arg(args, '--firebase-env', null);
  final debugFile = _arg(args, '--appcheck-debug-token-file', null);
  final keyFile = _arg(args, '--gemini-key-file', null);
  final _Target target;
  String? appCheckProblem;
  try {
    if (firebaseEnv != null) {
      final debugToken = debugFile == null
          ? null
          : _readSecretFile(debugFile, 'App Check debug token');
      target = _firebaseTarget(firebaseEnv, debugToken: debugToken);
      if (debugToken != null) {
        final project = target.base.split('/projects/')[1].split('/').first;
        final (token, problem) =
            await _exchangeDebugToken(target, project, debugToken);
        target.appCheckToken = token;
        appCheckProblem = problem;
      }
    } else {
      final key = keyFile != null
          ? _readSecretFile(keyFile, 'Gemini API key')
          : Platform.environment['GEMINI_API_KEY'];
      target = _Target(
        base: _developerApi,
        via: key == null || key.isEmpty
            ? 'Gemini Developer API, no key set'
            : 'Gemini Developer API (key from '
                '${keyFile != null ? 'a file' : 'GEMINI_API_KEY'})',
        key: key,
      );
    }
  } on Object catch (e) {
    stderr.writeln('Cannot read the settings: '
        '${e is FormatException ? e.message : e.runtimeType}');
    exitCode = 64;
    return;
  }

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
  final calls = <_Call>[await _generate(model, prompt, target)];
  if (!calls.last.ok && fallback.isNotEmpty) {
    calls.add(await _generate(fallback, prompt, target));
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
    ..writeln('Route: ${target.via}'
        '${target.appCheckToken != null ? ', with an App Check token from a debug token' : ''}.')
    ..writeln()
    ..writeAll([
      if (appCheckProblem != null)
        'App Check debug token refused: $appCheckProblem\n\n',
    ])
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
      'route': target.via,
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
