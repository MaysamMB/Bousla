import 'dart:convert';

import 'review_marks_local_stub.dart'
    if (dart.library.js_interop) 'review_marks_local_web.dart';

/// The concepts a student has ticked as "I've reviewed this concept", kept
/// in this browser only (localStorage), per session and participant, so a
/// reload restores the ticks and two sessions or two students on one
/// browser never mix.
///
/// A tick is the student's own note, not evidence: it is never sent to
/// Firebase or any server, never shown to the instructor, and never changes
/// a state, a score or the feedback. Only a follow-up session's results can
/// show whether reviewing helped.
class ReviewMarksStore {
  ReviewMarksStore({
    required String? Function(String key) read,
    required void Function(String key, String value) write,
  })  : _read = read,
        _write = write;

  /// This browser's localStorage (nothing is kept outside a browser).
  factory ReviewMarksStore.browser() =>
      ReviewMarksStore(read: readLocal, write: writeLocal);

  final String? Function(String key) _read;
  final void Function(String key, String value) _write;

  static String keyFor(String sessionId, String participantId) =>
      'bousla.reviewed.v1.$sessionId.$participantId';

  /// The ticked concept IDs; empty when nothing is stored, storage is
  /// blocked, or what is stored is not a list of IDs.
  Set<String> load(String sessionId, String participantId) {
    try {
      final raw = _read(keyFor(sessionId, participantId));
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final id in decoded)
          if (id is String && id.isNotEmpty) id,
      };
    } catch (_) {
      return {};
    }
  }

  void save(String sessionId, String participantId, Set<String> conceptIds) {
    try {
      _write(keyFor(sessionId, participantId),
          jsonEncode((conceptIds.toList()..sort())));
    } catch (_) {
      // Not remembered after a reload; the ticks still work on this page.
    }
  }
}
