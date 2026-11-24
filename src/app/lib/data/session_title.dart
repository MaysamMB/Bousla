import 'package:bousla_engine/bousla_engine.dart';

import 'models.dart';

/// A short title for a session, in both languages, made from the concepts
/// its questions cover, in question order: "Primary Key, Foreign Key +2".
/// The date and time are shown next to it, so it does not repeat them.
LocalizedText sessionTitleFor(
  List<QuestionView> questions,
  List<Concept> concepts, {
  int shown = 2,
}) {
  final byId = {for (final c in concepts) c.id: c};
  final ids = <String>[];
  for (final q in questions) {
    for (final id in q.conceptIds) {
      if (byId.containsKey(id) && !ids.contains(id)) ids.add(id);
    }
  }
  if (ids.isEmpty) return const LocalizedText(ar: 'جلسة', en: 'Session');
  String join(String Function(Concept) name, String separator, bool rtl) {
    final names = [for (final id in ids.take(shown)) name(byId[id]!)];
    final more = ids.length - shown;
    if (more <= 0) return names.join(separator);
    // In Arabic "+2" is isolated (U+2066…U+2069) so it is not shown as "2+".
    return '${names.join(separator)} ${rtl ? '\u2066+$more\u2069' : '+$more'}';
  }

  return LocalizedText(
    ar: join((c) => c.name.ar, '، ', true),
    en: join((c) => c.name.en, ', ', false),
  );
}
