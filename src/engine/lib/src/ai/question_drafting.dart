/// AI level 1: drafting bilingual multiple-choice questions from the
/// instructor's material (docs/architecture.md §4 and §9).
///
/// This file has no network code. It builds the instructions and the JSON
/// schema sent to the model, and checks what comes back. Whatever passes is
/// only a *draft*: the app saves it as `pending_review` and the instructor
/// decides. Nothing here approves content or scores students.
library;

import 'dart:convert';
import 'dart:math';

import '../models.dart';
import 'model_json.dart';

/// A concept the model may link a question to (approved concepts only).
class DraftingConcept {
  const DraftingConcept({required this.id, required this.name});

  final String id;
  final LocalizedText name;
}

/// One answer option of a generated question.
class GeneratedOption {
  const GeneratedOption({required this.id, required this.text});

  final String id;
  final LocalizedText text;
}

/// A question drafted by the model that passed [parseQuestionDrafts].
class GeneratedQuestion {
  const GeneratedQuestion({
    required this.conceptIds,
    required this.prompt,
    required this.options,
    required this.correctOptionId,
    this.sourceLocation,
    this.difficulty,
  });

  final List<String> conceptIds;
  final LocalizedText prompt;

  /// Option IDs are always a, b, c, ... in order, whatever the model used.
  /// The order is shuffled (see [parseQuestionDrafts]).
  final List<GeneratedOption> options;
  final String correctOptionId;

  /// Where in the material the question comes from, e.g. "page 4".
  final String? sourceLocation;

  /// `basic`, `intermediate` or `advanced` when the model gave one of them.
  final String? difficulty;
}

/// Why a draft from the model was dropped before reaching the instructor.
enum DraftIssue {
  /// The whole answer was not the JSON object asked for.
  invalidJson,

  /// A question entry is not an object or misses required fields.
  malformed,

  /// None of its concepts is one of the concepts given to the model.
  unknownConcept,
  promptArabicMissing,
  promptEnglishMissing,

  /// The Arabic prompt has no Arabic letters (e.g. English copied twice).
  promptArabicHasNoArabicLetters,
  tooFewOptions,
  tooManyOptions,
  optionTextMissing,

  /// The correct answer is not one of the options.
  correctOptionMissing,

  /// Same prompt as an earlier draft in the same answer.
  duplicate,

  /// The question text was only a list of the options.
  optionsInPrompt,
}

/// What the model returned, after the checks.
class DraftParseResult {
  const DraftParseResult({required this.accepted, required this.dropped});

  final List<GeneratedQuestion> accepted;

  /// One entry per dropped draft (or one [DraftIssue.invalidJson] for the
  /// whole answer). Shown to the instructor as counts, and kept as evidence
  /// of AI draft quality.
  final List<DraftIssue> dropped;
}

const minDraftOptions = 2;
const maxDraftOptions = 6;
final _arabicLetter = RegExp(r'[؀-ۿ]');

/// Instructions sent with the material. Written in English (models follow
/// English instructions most reliably); the questions themselves must be
/// written in both Arabic and English.
String buildQuestionDraftingInstructions({
  required int count,
  required List<DraftingConcept> concepts,
}) {
  final conceptLines = [
    for (final c in concepts) '- ${c.id}: ${c.name.en} / ${c.name.ar}',
  ].join('\n');
  return '''
You help a university instructor prepare a short in-class quiz from their own course material, which is attached.

Write $count multiple-choice questions that check understanding of the material. Rules:
1. Use only what the material says. Do not add facts that are not in it. Several questions may cover the same concept or the same part of the material, as long as each tests a different point. Return fewer than $count only if the material really cannot support more good questions.
2. Link every question to one or more of these concept IDs, and to nothing else:
$conceptLines
   Skip parts of the material that fit none of them, and use the parts that do.
3. Write every question and every option in BOTH Arabic (Modern Standard Arabic) and English, with the same meaning. In Arabic, a technical term may be followed by the English term in parentheses, for example: المفتاح الأساسي (Primary Key). Code, table and column names stay as they are in both languages.
4. Give 4 options with exactly one correct answer. Wrong options must be plausible to a student who has not understood the idea, not silly. Do not use "all of the above" or "none of the above". Vary the position of the correct answer between questions.
5. The question text must not reveal the answer, and must not list the options: put them only in "options".
6. source_location says where in the material the question comes from, for example "page 4" or "section 2.1", so the instructor can check it quickly.
7. difficulty is one of: basic, intermediate, advanced.

Your questions are drafts. The instructor reviews, edits or rejects every one before any student sees it.''';
}

/// JSON schema for the model's answer (Gemini `responseJsonSchema`).
Map<String, Object?> questionDraftingJsonSchema() => {
      'type': 'object',
      'properties': {
        'questions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'concept_ids': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'prompt_ar': {'type': 'string'},
              'prompt_en': {'type': 'string'},
              'options': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'id': {'type': 'string'},
                    'text_ar': {'type': 'string'},
                    'text_en': {'type': 'string'},
                  },
                  'required': ['id', 'text_ar', 'text_en'],
                },
              },
              'correct_option_id': {'type': 'string'},
              'source_location': {'type': 'string'},
              'difficulty': {
                'type': 'string',
                'enum': ['basic', 'intermediate', 'advanced'],
              },
            },
            'required': [
              'concept_ids',
              'prompt_ar',
              'prompt_en',
              'options',
              'correct_option_id',
              'source_location',
            ],
          },
        },
      },
      'required': ['questions'],
    };

/// Checks the model's answer. At most [maxCount] drafts are accepted.
/// Concept IDs not in [knownConceptIds] are removed; a draft left with none
/// is dropped. Options are shuffled and renamed a, b, c, ... (the correct
/// answer follows its option): models tend to put the correct answer first,
/// which students would learn to exploit. The shuffle is seeded by the
/// question text, so the same answer always gives the same order.
DraftParseResult parseQuestionDrafts(
  String modelText, {
  required Set<String> knownConceptIds,
  required int maxCount,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stripCodeFence(modelText));
  } on FormatException {
    return const DraftParseResult(
      accepted: [],
      dropped: [DraftIssue.invalidJson],
    );
  }
  final list = switch (decoded) {
    {'questions': final List<Object?> q} => q,
    final List<Object?> q => q,
    _ => null,
  };
  if (list == null) {
    return const DraftParseResult(
      accepted: [],
      dropped: [DraftIssue.invalidJson],
    );
  }

  final accepted = <GeneratedQuestion>[];
  final dropped = <DraftIssue>[];
  final seenPrompts = <String>{};
  for (final entry in list) {
    if (accepted.length >= maxCount) break;
    final (draft, issue) = _checkOne(entry, knownConceptIds);
    if (issue != null) {
      dropped.add(issue);
      continue;
    }
    final key = _normalize(draft!.prompt.en);
    if (!seenPrompts.add(key)) {
      dropped.add(DraftIssue.duplicate);
      continue;
    }
    accepted.add(draft);
  }
  return DraftParseResult(accepted: accepted, dropped: dropped);
}

(GeneratedQuestion?, DraftIssue?) _checkOne(
  Object? entry,
  Set<String> knownConceptIds,
) {
  if (entry is! Map) return (null, DraftIssue.malformed);
  String? text(Object? v) => v is String ? v.trim() : null;

  final rawConcepts = entry['concept_ids'];
  final promptAr = text(entry['prompt_ar']);
  final promptEn = text(entry['prompt_en']);
  final rawOptions = entry['options'];
  final correct = text(entry['correct_option_id']);
  if (rawConcepts is! List ||
      promptAr == null ||
      promptEn == null ||
      rawOptions is! List ||
      correct == null) {
    return (null, DraftIssue.malformed);
  }

  final conceptIds = [
    for (final c in rawConcepts)
      if (c is String && knownConceptIds.contains(c.trim())) c.trim(),
  ].toSet().toList();
  if (conceptIds.isEmpty) return (null, DraftIssue.unknownConcept);

  if (promptAr.isEmpty) return (null, DraftIssue.promptArabicMissing);
  if (!_arabicLetter.hasMatch(promptAr)) {
    return (null, DraftIssue.promptArabicHasNoArabicLetters);
  }
  if (promptEn.isEmpty) return (null, DraftIssue.promptEnglishMissing);

  if (rawOptions.length < minDraftOptions) {
    return (null, DraftIssue.tooFewOptions);
  }
  if (rawOptions.length > maxDraftOptions) {
    return (null, DraftIssue.tooManyOptions);
  }
  final parsed = <(LocalizedText, bool)>[];
  var hasCorrect = false;
  for (final o in rawOptions) {
    if (o is! Map) return (null, DraftIssue.malformed);
    final ar = text(o['text_ar']) ?? '';
    final en = text(o['text_en']) ?? '';
    // Option text may be code (e.g. student_id) in both languages, so only
    // emptiness is checked here, as in the app's validateDraft.
    if (ar.isEmpty || en.isEmpty) return (null, DraftIssue.optionTextMissing);
    final isCorrect = !hasCorrect && text(o['id']) == correct;
    hasCorrect = hasCorrect || isCorrect;
    parsed.add((LocalizedText(ar: ar, en: en), isCorrect));
  }
  if (!hasCorrect) return (null, DraftIssue.correctOptionMissing);

  // Models sometimes repeat the options inside the question text
  // ("...? a) ... b) ..."); students would then see them twice.
  final cleanAr = _withoutListedOptions(promptAr, [
    for (final o in parsed) o.$1.ar,
  ]);
  final cleanEn = _withoutListedOptions(promptEn, [
    for (final o in parsed) o.$1.en,
  ]);
  if (cleanAr.isEmpty || cleanEn.isEmpty) {
    return (null, DraftIssue.optionsInPrompt);
  }
  parsed.shuffle(Random(_stableHash(cleanEn)));
  final options = <GeneratedOption>[];
  late String correctId;
  for (var i = 0; i < parsed.length; i++) {
    final id = String.fromCharCode('a'.codeUnitAt(0) + i);
    if (parsed[i].$2) correctId = id;
    options.add(GeneratedOption(id: id, text: parsed[i].$1));
  }

  final difficulty = text(entry['difficulty']);
  final location = text(entry['source_location']);
  return (
    GeneratedQuestion(
      conceptIds: conceptIds,
      prompt: LocalizedText(ar: cleanAr, en: cleanEn),
      options: options,
      correctOptionId: correctId,
      sourceLocation: location == null || location.isEmpty ? null : location,
      difficulty:
          const {'basic', 'intermediate', 'advanced'}.contains(difficulty)
              ? difficulty
              : null,
    ),
    null,
  );
}

/// [prompt] without a trailing list of the options. Only when at least two
/// option texts appear in it; the cut is made at the first one, before its
/// marker such as "a)", "(b)", "1." or "أ)".
String _withoutListedOptions(String prompt, List<String> options) {
  final positions = [
    for (final o in options)
      if (o.trim().length >= 2) prompt.indexOf(o.trim()),
  ].where((i) => i > 0).toList();
  if (positions.length < 2) return prompt;
  var cut = positions.reduce(min);
  final marker = RegExp(
    r'[\s(\[]*(?:[أابجدهـ]|[a-fA-F]|[1-6])\s*[).:\-]\s*$',
  ).firstMatch(prompt.substring(0, cut));
  if (marker != null) cut = marker.start;
  return prompt.substring(0, cut).trim();
}

/// FNV-1a over the UTF-16 code units: the same on every platform and run
/// (String.hashCode is not guaranteed to be).
int _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), ' ').trim();
