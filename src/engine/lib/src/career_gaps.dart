import 'mastery_estimator.dart';
import 'models.dart';

/// Career path, first version (architecture §9 "Later"; project scope 12).
///
/// Compares the skills a role asks for with the evidence in the student's
/// own profile. Deterministic: no AI here, and nothing about the job market
/// is computed; the role's skills come from a dataset that names its source
/// ([CareerDataSource]). Every result keeps the concept evidence it used, so
/// the screen can say *why*.

/// Where a role's skill list comes from. A team draft is allowed while the
/// real source is being collected, but it must say so.
enum CareerSourceKind {
  /// ESCO, the European Commission's skills and occupations classification.
  esco,

  /// Skills counted from real, dated job adverts.
  jobAdverts,

  /// Written by the team; not yet checked against a labour-market source.
  teamDraft,
}

class CareerDataSource {
  const CareerDataSource({
    required this.kind,
    required this.name,
    this.url,
    this.retrieved,
  });

  final CareerSourceKind kind;

  /// E.g. "ESCO v1.2" or "Team draft, 27 Nov 2026".
  final String name;
  final String? url;

  /// When the data was read (ISO date), for a source that changes.
  final String? retrieved;

  bool get isDraft => kind == CareerSourceKind.teamDraft;
}

/// One skill a role asks for, and the Bousla concepts that give evidence
/// for it (the team's mapping). No concepts: the skill is outside what
/// Bousla's courses can show yet.
class CareerSkill {
  const CareerSkill({
    required this.id,
    required this.name,
    required this.essential,
    this.conceptIds = const [],
    this.sourceUri,
    this.localCount,
  });

  final String id;
  final LocalizedText name;

  /// Essential for the role (otherwise optional/useful).
  final bool essential;
  final List<String> conceptIds;

  /// The skill in its source (e.g. an ESCO skill URI), when there is one.
  final String? sourceUri;

  /// In how many of the role's local job adverts this skill was asked for
  /// (see [CareerRole.localAdverts]); null when none asked for it.
  final int? localCount;
}

/// Below this many local adverts a role's local counts are not shown: a
/// share of 3 or 5 adverts says little and reads as more than it is.
const minLocalAdverts = 10;

/// The local job adverts behind [CareerSkill.localCount]: how many, when,
/// from where, and how many people linked them to skills.
class LocalAdverts {
  const LocalAdverts({
    required this.total,
    required this.publishedFrom,
    required this.publishedTo,
    required this.sites,
    required this.labellers,
    this.preliminary = true,
  });

  final int total;
  final String publishedFrom;
  final String publishedTo;
  final List<String> sites;

  /// People who linked adverts to skills; 1 = not yet cross-checked.
  final int labellers;
  final bool preliminary;

  bool get enough => total >= minLocalAdverts;
}

class CareerRole {
  const CareerRole({
    required this.id,
    required this.title,
    required this.source,
    required this.skills,
    this.conceptNames = const {},
    this.localAdverts,
  });

  final String id;
  final LocalizedText title;
  final CareerDataSource source;
  final List<CareerSkill> skills;

  /// Names of the concepts the skills use, copied from the course data
  /// (tests check they match), for concepts the student never met.
  final Map<String, LocalizedText> conceptNames;

  /// Local job adverts collected for this role, when there are any.
  final LocalAdverts? localAdverts;

  /// The skills the local adverts asked for most, most asked first (ties in
  /// the dataset's order). Empty without enough adverts.
  List<CareerSkill> topLocalSkills([int n = 5]) {
    if (localAdverts?.enough != true) return const [];
    final asked = [
      for (var i = 0; i < skills.length; i++)
        if ((skills[i].localCount ?? 0) > 0) (i, skills[i]),
    ]..sort((a, b) {
        final c = b.$2.localCount! - a.$2.localCount!;
        return c != 0 ? c : a.$1 - b.$1;
      });
    return [for (final x in asked.take(n)) x.$2];
  }
}

/// A concept's standing in the student's profile: the state and evidence
/// from the most recent saved session that assessed it.
class ConceptStanding {
  const ConceptStanding({
    required this.conceptId,
    required this.state,
    required this.attempts,
    required this.correct,
  });

  final String conceptId;
  final MasteryState state;
  final int attempts;
  final int correct;

  bool get assessed => state != MasteryState.insufficientEvidence;
}

/// What the profile shows for one skill. Estimates, not judgements.
enum SkillStatus {
  /// At least one linked concept is in possible difficulty.
  possibleGap,

  /// Linked concepts exist, but none has enough evidence yet.
  noEvidence,

  /// Some evidence, not yet demonstrated for every linked concept.
  partial,

  /// Every linked concept is demonstrated.
  evidence,

  /// No Bousla concept covers this skill yet.
  outsideBousla,
}

class SkillResult {
  const SkillResult({
    required this.skill,
    required this.status,
    required this.concepts,
    required this.toWorkOn,
  });

  final CareerSkill skill;
  final SkillStatus status;

  /// The linked concepts' standings (missing ones are not assessed).
  final List<ConceptStanding> concepts;

  /// Linked concepts to review (possible difficulty) first, then to get
  /// evidence for (not assessed / emerging), in the skill's order.
  final List<String> toWorkOn;
}

class CareerGapReport {
  const CareerGapReport({required this.role, required this.skills});

  final CareerRole role;

  /// Essential skills first; within each, possible gaps first, then no
  /// evidence, partial, evidence, outside Bousla.
  final List<SkillResult> skills;

  int count(SkillStatus status, {bool? essential}) => skills
      .where((s) =>
          s.status == status &&
          (essential == null || s.skill.essential == essential))
      .length;

  /// Whether the profile has any assessed concept that this role uses.
  bool get hasEvidence => skills.any((s) => s.concepts.any((c) => c.assessed));
}

SkillStatus _status(CareerSkill skill, List<ConceptStanding> linked) {
  if (skill.conceptIds.isEmpty) return SkillStatus.outsideBousla;
  final assessed = linked.where((c) => c.assessed).toList();
  if (assessed.any((c) => c.state == MasteryState.possibleDifficulty)) {
    return SkillStatus.possibleGap;
  }
  if (assessed.isEmpty) return SkillStatus.noEvidence;
  final allShown = skill.conceptIds.every((id) => linked.any(
      (c) => c.conceptId == id && c.state == MasteryState.demonstratedMastery));
  return allShown ? SkillStatus.evidence : SkillStatus.partial;
}

/// Compares [role] with the student's [standings] (by concept ID).
CareerGapReport careerGaps(
  CareerRole role,
  Map<String, ConceptStanding> standings,
) {
  final results = <SkillResult>[];
  for (final skill in role.skills) {
    final linked = [
      for (final id in skill.conceptIds)
        if (standings[id] != null) standings[id]!,
    ];
    final status = _status(skill, linked);
    final review = [
      for (final id in skill.conceptIds)
        if (standings[id]?.state == MasteryState.possibleDifficulty) id,
    ];
    final moreEvidence = [
      for (final id in skill.conceptIds)
        if (standings[id] == null ||
            standings[id]!.state == MasteryState.insufficientEvidence ||
            standings[id]!.state == MasteryState.emerging)
          id,
    ];
    results.add(SkillResult(
      skill: skill,
      status: status,
      concepts: linked,
      toWorkOn: [...review, ...moreEvidence],
    ));
  }
  final order = SkillStatus.values;
  final indexed = [for (var i = 0; i < results.length; i++) (i, results[i])];
  indexed.sort((a, b) {
    final e = (a.$2.skill.essential ? 0 : 1) - (b.$2.skill.essential ? 0 : 1);
    if (e != 0) return e;
    final s = order.indexOf(a.$2.status) - order.indexOf(b.$2.status);
    if (s != 0) return s;
    return a.$1 - b.$1; // stable: the dataset's order
  });
  return CareerGapReport(role: role, skills: [for (final x in indexed) x.$2]);
}

/// The most recent standing per concept, from a student's saved sessions
/// listed **oldest first**. A later session that did not assess a concept
/// (insufficient evidence) does not hide an earlier assessed result.
Map<String, ConceptStanding> latestStandings(
  List<List<ConceptStanding>> sessionsOldestFirst,
) {
  final out = <String, ConceptStanding>{};
  for (final session in sessionsOldestFirst) {
    for (final c in session) {
      final before = out[c.conceptId];
      if (before == null || c.assessed || !before.assessed) {
        out[c.conceptId] = c;
      }
    }
  }
  return out;
}

/// Reads a role from its JSON dataset (see `src/app/assets/careers/`).
CareerRole careerRoleFromJson(Map<String, dynamic> j) {
  LocalizedText text(Object? v) {
    final m = v as Map;
    return LocalizedText(ar: '${m['ar']}', en: '${m['en']}');
  }

  final s = j['source'] as Map;
  final kind = switch (s['kind']) {
    'esco' => CareerSourceKind.esco,
    'job_adverts' => CareerSourceKind.jobAdverts,
    'team_draft' => CareerSourceKind.teamDraft,
    final k => throw FormatException('unknown source kind: $k'),
  };
  return CareerRole(
    id: j['id'] as String,
    title: text(j['title']),
    source: CareerDataSource(
      kind: kind,
      name: s['name'] as String,
      url: s['url'] as String?,
      retrieved: s['retrieved'] as String?,
    ),
    localAdverts: switch (j['local_adverts']) {
      final Map<String, dynamic> a => LocalAdverts(
          total: (a['total'] as num).toInt(),
          publishedFrom: '${a['published_from']}',
          publishedTo: '${a['published_to']}',
          sites: [for (final s in a['sites'] as List) '$s'],
          labellers: (a['labellers'] as num?)?.toInt() ?? 1,
          preliminary: a['status'] != 'reviewed',
        ),
      _ => null,
    },
    conceptNames: {
      for (final e in ((j['concept_names'] as Map?) ?? const {}).entries)
        '${e.key}': text(e.value),
    },
    skills: [
      for (final k in j['skills'] as List)
        CareerSkill(
          id: (k as Map)['id'] as String,
          name: text(k['name']),
          essential: k['essential'] == true,
          conceptIds: [for (final c in (k['concepts'] as List? ?? [])) '$c'],
          sourceUri: k['source_uri'] as String?,
          localCount: (k['local_count'] as num?)?.toInt(),
        ),
    ],
  );
}
