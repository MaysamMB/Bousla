import 'dart:typed_data';

import 'package:bousla_engine/bousla_engine.dart';

/// A file the instructor picked. It is sent to the model and never stored
/// (no Cloud Storage on the Spark plan, docs/architecture.md §4).
class MaterialFile {
  const MaterialFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;

  /// `application/pdf` or `text/plain`.
  final String mimeType;
  final Uint8List bytes;

  static const maxBytes = 15 * 1024 * 1024;

  /// Supported file types by extension, or null.
  static String? mimeTypeFor(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.txt') || name.endsWith('.md')) return 'text/plain';
    return null;
  }
}

/// Why drafting failed, so the screen can say what to do.
enum GenerationProblem {
  /// Firebase AI Logic is not enabled for the project.
  notEnabled,

  /// The free quota is used up for now.
  quota,

  /// The free daily request limit of the model is used up (it renews
  /// within 24 hours). Retrying the same model is pointless.
  dailyQuota,

  /// The model is temporarily overloaded on Google's side.
  busy,
  fileTooLarge,
  unsupportedFile,

  /// The model answered nothing usable (e.g. blocked by safety filters).
  emptyAnswer,
  network,
  unknown,
}

class QuestionGenerationException implements Exception {
  const QuestionGenerationException(this.problem, [this.detail]);

  final GenerationProblem problem;
  final String? detail;

  @override
  String toString() => 'QuestionGenerationException($problem, $detail)';
}

/// AI level 1: drafts questions from the instructor's material. The result
/// has passed the engine's checks ([parseQuestionDrafts]) but is only a
/// draft; the instructor reviews every question.
abstract interface class QuestionGenerator {
  /// Model name, kept with the drafts for transparency.
  String get modelName;

  /// Throws [QuestionGenerationException].
  Future<DraftParseResult> draftQuestions({
    required MaterialFile material,
    required List<Concept> concepts,
    required int count,
  });
}
