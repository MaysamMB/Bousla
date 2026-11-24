import '../../../data/feedback.dart';

/// Orders a session's concepts for the knowledge map, foundations first.
///
/// Level 0 holds the concepts with no prerequisite among [concepts]; every
/// other concept sits one level after its deepest prerequisite. A
/// prerequisite that was not part of the session is left out (there is no
/// evidence about it), and a cycle in the data is broken instead of looping.
/// Within a level, the input order is kept.
List<List<FeedbackConcept>> knowledgeMapLevels(
  List<FeedbackConcept> concepts,
) {
  final byId = {for (final c in concepts) c.conceptId: c};
  final level = <String, int>{};
  final visiting = <String>{};

  int levelOf(String id) {
    final known = level[id];
    if (known != null) return known;
    // Reached again while still being computed: a cycle. Count it as a root.
    if (!visiting.add(id)) return -1;
    var deepest = -1;
    for (final p in byId[id]!.prerequisites) {
      if (byId.containsKey(p)) {
        final l = levelOf(p);
        if (l > deepest) deepest = l;
      }
    }
    visiting.remove(id);
    return level[id] = deepest + 1;
  }

  for (final c in concepts) {
    levelOf(c.conceptId);
  }
  final levels = <List<FeedbackConcept>>[];
  for (final c in concepts) {
    final l = level[c.conceptId]!;
    while (levels.length <= l) {
      levels.add([]);
    }
    levels[l].add(c);
  }
  return levels;
}
