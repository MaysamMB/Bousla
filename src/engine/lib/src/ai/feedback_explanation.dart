/// AI level 2: short personal explanations on top of the engine's results
/// (docs/architecture.md §9).
///
/// This file has no network code. It
/// 1. builds an anonymous profile per student from the engine's verified
///    results (concept states, prerequisite signals, approved resources),
/// 2. merges identical profiles, so one model request covers a whole class
///    and students with the same results get the same explanation,
/// 3. builds the instructions and JSON schema sent to the model,
/// 4. checks every explanation the model returns (guards below), and
/// 5. writes a deterministic template explanation whenever there is no
///    model answer or an explanation fails a guard.
///
/// The explanation only puts the engine's results into words. Nothing here
/// changes a score, a state, a prerequisite signal or a recommendation.
library;

import 'dart:convert';

import '../learning_recommender.dart';
import '../mastery_estimator.dart';
import '../models.dart';
import '../prerequisite_analyzer.dart';
import 'model_json.dart';

// ---------------------------------------------------------------- profiles

/// One concept in a profile: its name and the engine's state. Counts are
/// left out on purpose, so that students with the same states share one
/// explanation; the screen shows the counts next to the explanation.
class ProfileConcept {
  const ProfileConcept({
    required this.id,
    required this.name,
    required this.state,
  });

  final String id;
  final LocalizedText name;
  final MasteryState state;

  Map<String, Object?> toJson() => {
        'concept_id': id,
        'name_ar': name.ar,
        'name_en': name.en,
        'state': state.name,
      };
}

/// A prerequisite signal shown to the student (see [isStudentHint]).
class ProfileHint {
  const ProfileHint({
    required this.conceptId,
    required this.prerequisiteId,
    required this.signal,
  });

  final String conceptId;
  final String prerequisiteId;
  final PrerequisiteSignal signal;

  Map<String, Object?> toJson() => {
        'concept_id': conceptId,
        'prerequisite_id': prerequisiteId,
        'signal': signal.name,
      };
}

/// An approved resource of a recommendation.
class ProfileResource {
  const ProfileResource({required this.id, required this.title, this.url});

  final String id;
  final LocalizedText title;
  final String? url;

  /// The URL is not sent to the model: it has no reason to write links, and
  /// the resource guard refuses any link it writes that is not this one.
  Map<String, Object?> toJson() => {
        'resource_id': id,
        'title_ar': title.ar,
        'title_en': title.en,
      };
}

class ProfileRecommendation {
  const ProfileRecommendation({
    required this.conceptId,
    required this.reason,
    this.relatedConceptId,
    this.resources = const [],
  });

  final String conceptId;
  final RecommendationReason reason;
  final String? relatedConceptId;
  final List<ProfileResource> resources;

  Map<String, Object?> toJson() => {
        'concept_id': conceptId,
        'reason': reason.name,
        if (relatedConceptId != null) 'related_concept_id': relatedConceptId,
        'resources': [for (final r in resources) r.toJson()],
      };
}

/// What one student's explanation may be based on. Holds no name, no UID
/// and no answers: only the engine's results and approved resources.
class ExplanationProfile {
  const ExplanationProfile({
    this.id = '',
    required this.concepts,
    this.hints = const [],
    this.recommendations = const [],
  });

  /// Assigned by [groupProfiles] (`p1`, `p2`, ...). Not linked to a student.
  final String id;

  /// Sorted by concept ID.
  final List<ProfileConcept> concepts;
  final List<ProfileHint> hints;

  /// In the engine's order (foundations first).
  final List<ProfileRecommendation> recommendations;

  ExplanationProfile withId(String id) => ExplanationProfile(
        id: id,
        concepts: concepts,
        hints: hints,
        recommendations: recommendations,
      );

  Map<String, Object?> _content() => {
        'concepts': [for (final c in concepts) c.toJson()],
        'prerequisite_hints': [for (final h in hints) h.toJson()],
        'recommendations': [for (final r in recommendations) r.toJson()],
      };

  /// Equal for two profiles with the same educational content.
  String get signature => jsonEncode(_content());

  /// Exactly what the model receives for this profile.
  Map<String, Object?> toPromptJson() => {'profile_id': id, ..._content()};

  Iterable<ProfileResource> get resources =>
      recommendations.expand((r) => r.resources);

  ProfileConcept? concept(String id) {
    for (final c in concepts) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// The prerequisite signals shown to a student: a possible contributing
/// gap, or a prerequisite without enough evidence. "Uncertain" and
/// "unlikely cause" give the student nothing to act on.
bool isStudentHint(PrerequisiteSignal signal) =>
    signal == PrerequisiteSignal.possibleContributingGap ||
    signal == PrerequisiteSignal.needsMoreEvidence;

/// Builds one student's profile from the engine's results. Concepts missing
/// from [concepts] (no name to show) are left out.
ExplanationProfile buildExplanationProfile({
  required Map<String, ConceptMastery> masteries,
  required List<PrerequisiteFinding> findings,
  required List<Recommendation> recommendations,
  required Iterable<Concept> concepts,
}) {
  final byId = {for (final c in concepts) c.id: c};
  final ids = masteries.keys.where(byId.containsKey).toList()..sort();
  final hints = [
    for (final f in findings)
      if (isStudentHint(f.signal))
        ProfileHint(
          conceptId: f.conceptId,
          prerequisiteId: f.prerequisiteId,
          signal: f.signal,
        ),
  ]..sort((a, b) {
      final byConcept = a.conceptId.compareTo(b.conceptId);
      return byConcept != 0
          ? byConcept
          : a.prerequisiteId.compareTo(b.prerequisiteId);
    });
  return ExplanationProfile(
    concepts: [
      for (final id in ids)
        ProfileConcept(
          id: id,
          name: byId[id]!.name,
          state: masteries[id]!.state,
        ),
    ],
    hints: hints,
    recommendations: [
      for (final r in recommendations)
        ProfileRecommendation(
          conceptId: r.conceptId,
          reason: r.reason,
          relatedConceptId: r.relatedConceptId,
          resources: [
            for (final res in r.resources)
              if (res.status == ReviewStatus.approved)
                ProfileResource(id: res.id, title: res.title, url: res.url),
          ],
        ),
    ],
  );
}

/// Identical profiles merged into one.
class ProfileGroups<K> {
  const ProfileGroups({required this.profiles, required this.profileIdOf});

  /// Unique profiles with IDs `p1`, `p2`, ... These are what the model sees.
  final List<ExplanationProfile> profiles;

  /// Which profile each student has. Stays in the app; never sent.
  final Map<K, String> profileIdOf;

  ExplanationProfile profileOf(K student) {
    final id = profileIdOf[student];
    return profiles.firstWhere((p) => p.id == id);
  }
}

/// Merges identical profiles. IDs follow the sorted [ExplanationProfile.
/// signature], so they do not depend on the order of students (or on
/// their UIDs).
ProfileGroups<K> groupProfiles<K>(Map<K, ExplanationProfile> byStudent) {
  final signatures = {
    for (final e in byStudent.entries) e.key: e.value.signature,
  };
  final unique = <String, ExplanationProfile>{};
  for (final e in byStudent.entries) {
    unique.putIfAbsent(signatures[e.key]!, () => e.value);
  }
  final sorted = unique.keys.toList()..sort();
  final idOfSignature = {
    for (var i = 0; i < sorted.length; i++) sorted[i]: 'p${i + 1}',
  };
  return ProfileGroups(
    profiles: [
      for (final s in sorted) unique[s]!.withId(idOfSignature[s]!),
    ],
    profileIdOf: {
      for (final e in signatures.entries) e.key: idOfSignature[e.value]!,
    },
  );
}

// ------------------------------------------------------------ the request

const maxExplanationLength = 600;

/// Instructions for ONE request covering all unique profiles of a session.
/// Written in English (models follow English instructions most reliably);
/// the explanations themselves are in Arabic and English.
String buildFeedbackExplanationPrompt(List<ExplanationProfile> profiles) {
  final data = const JsonEncoder.withIndent(' ')
      .convert([for (final p in profiles) p.toPromptJson()]);
  return '''
You help a university instructor give each student a short, kind explanation of their results in an in-class quiz. The results below were computed by a rule-based engine and are final: do not change, question or add to them.

Each profile is the anonymous result of one or more students. For EVERY profile, write one explanation in Modern Standard Arabic (text_ar) and the same explanation in English (text_en). Rules:
1. 2 to 4 short sentences, at most $maxExplanationLength characters in each language.
2. Mention only the concepts and resources listed in that profile, by the names given. Do not mention other topics, IDs, numbers of answers or scores.
3. The states mean: insufficientEvidence = not enough evidence yet; possibleDifficulty = may need review; emerging = understanding still forming; demonstratedMastery = showed good understanding. A prerequisite hint is only a possibility: "reviewing X first may help", never a certainty.
4. Be encouraging and careful. Never say the student has a gap, failed, is weak, does not understand, or anything definitive or judgmental. Use "may", "could help", "not enough evidence yet".
5. Do not write any link, URL or website. You may name a resource by its title.
6. text_ar must be Arabic; a technical term may be followed by the English term in parentheses, e.g. المفتاح الأساسي (Primary Key). text_en must contain no Arabic.
7. Answer with a JSON array of {"profile_id", "text_ar", "text_en"}, one entry per profile_id.

PROFILES:
$data''';
}

/// JSON schema for the model's answer (Gemini `responseJsonSchema`).
Map<String, Object?> feedbackExplanationJsonSchema() => {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'profile_id': {'type': 'string'},
          'text_ar': {'type': 'string'},
          'text_en': {'type': 'string'},
        },
        'required': ['profile_id', 'text_ar', 'text_en'],
      },
    };

// ----------------------------------------------------------------- guards

/// Why an explanation from the model was replaced by the template.
enum ExplanationIssue {
  /// The whole answer was not the JSON asked for (applies to every profile).
  invalidAnswer,

  /// The answer had no usable entry for this profile.
  missing,

  /// Guard 1: names a course concept that is not in the profile, or an ID.
  unknownConcept,

  /// Guard 2: a link, resource ID or resource title not in the profile.
  unapprovedResource,

  /// Guard 3: text_ar is not Arabic, or text_en contains Arabic.
  wrongLanguage,

  /// Guard 4: definitive, judgmental or discouraging wording.
  forbiddenWording,

  /// Guard 5: empty, or longer than [maxExplanationLength] characters.
  tooLong,
}

final _arabicChar = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
final _letter = RegExp(r'\p{L}', unicode: true);

/// Lower case; Arabic without diacritics and tatweel, with one form of alef,
/// yaa and taa marbuta, so spelling variants match.
String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[ً-ْٰـ]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه');

const _arabicPrefixes = ['وال', 'بال', 'كال', 'فال', 'لل', 'ال'];

/// Words for matching names: Arabic without the article and its attached
/// prepositions (للمفتاح, بالمفتاح → مفتاح), English without a plural s.
List<String> _words(String s) {
  final out = <String>[];
  for (final w in _normalize(s).split(RegExp(r'[^a-z0-9ء-ي]+'))) {
    if (w.isEmpty) continue;
    var word = w;
    if (_arabicChar.hasMatch(word)) {
      for (final p in _arabicPrefixes) {
        if (word.startsWith(p) && word.length - p.length >= 2) {
          word = word.substring(p.length);
          break;
        }
      }
    } else if (word.length > 3) {
      if (word.endsWith('ies')) {
        word = '${word.substring(0, word.length - 3)}y';
      } else if (word.endsWith('s') && !word.endsWith('ss')) {
        word = word.substring(0, word.length - 1);
      }
    }
    out.add(word);
  }
  return out;
}

/// The ways a name can be written: as given, and without a part in
/// parentheses ("ربط الجداول (JOIN)" → "ربط الجداول").
List<List<String>> _variants(LocalizedText name) {
  final out = <List<String>>[];
  for (final n in [name.ar, name.en]) {
    for (final v in {n, n.replaceAll(RegExp(r'\([^)]*\)'), ' ')}) {
      final w = _words(v);
      if (w.isNotEmpty) out.add(w);
    }
  }
  return out;
}

/// Word ranges [start, end) where [phrase] occurs in [words].
Iterable<(int, int)> _find(List<String> words, List<String> phrase) sync* {
  for (var i = 0; i + phrase.length <= words.length; i++) {
    var all = true;
    for (var j = 0; j < phrase.length; j++) {
      if (words[i + j] != phrase[j]) {
        all = false;
        break;
      }
    }
    if (all) yield (i, i + phrase.length);
  }
}

/// True if a [forbidden] name occurs in [text] outside the places where an
/// [allowed] name occurs (so "Key" is not found inside "Primary Key").
bool _mentionsOther(
  String text,
  Iterable<LocalizedText> allowed,
  Iterable<LocalizedText> forbidden,
) {
  final words = _words(text);
  final covered = <int>{};
  for (final name in allowed) {
    for (final v in _variants(name)) {
      for (final (s, e) in _find(words, v)) {
        for (var i = s; i < e; i++) {
          covered.add(i);
        }
      }
    }
  }
  for (final name in forbidden) {
    for (final v in _variants(name)) {
      for (final (s, e) in _find(words, v)) {
        var inside = true;
        for (var i = s; i < e; i++) {
          if (!covered.contains(i)) inside = false;
        }
        if (!inside) return true;
      }
    }
  }
  return false;
}

/// Guard 1. Passes when the text names no course concept other than the
/// profile's (in Arabic or English, in either text) and contains no
/// concept-ID-like token (`foreign_key`) that is not one of them.
///
/// Limitation: a topic that is in neither list (e.g. "indexes" in a course
/// without that concept) cannot be recognised by name; the prompt forbids
/// it and the instructor can turn AI explanations off.
bool passesConceptGuard(
  LocalizedText text, {
  required ExplanationProfile profile,
  required Iterable<Concept> courseConcepts,
}) {
  final courseIds = {for (final c in courseConcepts) c.id};
  final allowedIds = {
    for (final c in profile.concepts)
      if (courseIds.contains(c.id)) c.id,
  };
  final allowed = [
    for (final c in profile.concepts)
      if (allowedIds.contains(c.id)) c.name,
  ];
  final forbidden = [
    for (final c in courseConcepts)
      if (!allowedIds.contains(c.id)) c.name,
  ];
  final resourceIds = {for (final r in profile.resources) r.id};
  final idLike = RegExp(r'\b[a-z0-9]+(?:_[a-z0-9]+)+\b');
  for (final t in [text.ar, text.en]) {
    if (_mentionsOther(t, allowed, forbidden)) return false;
    for (final m in idLike.allMatches(t.toLowerCase())) {
      final token = m.group(0)!;
      if (resourceIds.contains(token)) continue; // judged by guard 2
      if (courseIds.contains(token) || token.startsWith('res_')) {
        if (!allowedIds.contains(token)) return false;
      }
    }
  }
  return true;
}

final _url = RegExp(
  r'(?:https?://|www\.)[^\s)\]]+'
  r'|\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|org|net|edu|gov|io|co|ly|info|dev|app|me|sa|ae|uk|tv|be|gl)\b(?:/[^\s)\]]*)?',
  caseSensitive: false,
);

String _cleanUrl(String u) => u
    .toLowerCase()
    .replaceAll(RegExp(r'[.,;:!?،؛]+$'), '')
    .replaceAll(RegExp(r'^https?://'), '')
    .replaceAll(RegExp(r'^www\.'), '')
    .replaceAll(RegExp(r'/+$'), '');

/// Guard 2. Passes when every link in the text is the URL of a resource in
/// the profile, every `res_...` ID is one of its resources, and no title of
/// another course resource ([courseResources], when given) is named.
bool passesResourceGuard(
  LocalizedText text, {
  required ExplanationProfile profile,
  Iterable<Resource> courseResources = const [],
}) {
  final allowedUrls = {
    for (final r in profile.resources)
      if (r.url != null && r.url!.trim().isNotEmpty) _cleanUrl(r.url!.trim()),
  };
  final allowedIds = {for (final r in profile.resources) r.id};
  final allowedTitles = [for (final r in profile.resources) r.title];
  final otherTitles = [
    for (final r in courseResources)
      if (!allowedIds.contains(r.id)) r.title,
  ];
  for (final t in [text.ar, text.en]) {
    for (final m in _url.allMatches(t)) {
      if (!allowedUrls.contains(_cleanUrl(m.group(0)!))) return false;
    }
    for (final m in RegExp(r'\bres_[a-z0-9_]+').allMatches(t.toLowerCase())) {
      if (!allowedIds.contains(m.group(0))) return false;
    }
    if (_mentionsOther(t, allowedTitles, otherTitles)) return false;
  }
  return true;
}

/// Guard 3. text_ar must be Arabic (Arabic letters, at least half of all
/// letters, so English terms in parentheses are fine); text_en must contain
/// no Arabic character.
bool passesLanguageGuard(LocalizedText text) {
  final letters = _letter.allMatches(text.ar).length;
  final arabic = _letter
      .allMatches(text.ar)
      .where((m) => _arabicChar.hasMatch(m.group(0)!))
      .length;
  if (arabic == 0 || arabic * 2 < letters) return false;
  return !_arabicChar.hasMatch(text.en);
}

/// Definitive, judgmental or discouraging wording. Matched after
/// [_normalize], so the Arabic entries are written without hamza on alef and
/// with ه for ة.
final _forbiddenEnglish = [
  RegExp(r'\bgaps?\b'),
  RegExp(r'\bfail(?:s|ed|ing|ure|ures)?\b'),
  RegExp(
    r"\byou (?:do not|don't|did not|didn't|cannot|can not|can't|still don't) (?:understand|know|get)\b",
  ),
  RegExp(r'\byou (?:lack|are lacking|are behind|are not able)\b'),
  RegExp(
    r'\b(?:weak|weakness|poor|poorly|bad|terrible|awful|stupid|lazy|dumb|incompetent|hopeless|careless)\b',
  ),
  RegExp(r'\bdeficien'),
  RegExp(r'\bdiagnos'),
  RegExp(
    r'\b(?:definitely|certainly|obviously|clearly|undoubtedly|surely|always|never)\b',
  ),
  RegExp(r'\b(?:proves?|proven|confirm(?:s|ed)?)\b'),
];

const _forbiddenArabic = [
  'فجوه',
  'ثغره',
  'لا تفهم',
  'لم تفهم',
  'لا تعرف',
  'لم تعرف',
  'لا تستطيع',
  'لن تستطيع',
  'لا يمكنك',
  'ضعيف',
  'ضعف',
  'فشل',
  'فاشل',
  'راسب',
  'رسبت',
  'رسوب',
  'غبي',
  'سيء',
  'سيئ',
  'كسول',
  'عاجز',
  'قصور',
  'تعاني',
  'تشخيص',
  'بالتاكيد',
  'مؤكد',
  'حتما',
  'قطعا',
  'بلا شك',
  'دائما',
  'ابدا',
];

/// Guard 4. Passes when neither text contains forbidden wording.
bool passesWordingGuard(LocalizedText text) {
  final en = _normalize(text.en).replaceAll('’', "'");
  final ar = _normalize(text.ar).replaceAll(RegExp(r'\s+'), ' ');
  final enInAr = _normalize(text.ar).replaceAll('’', "'");
  for (final r in _forbiddenEnglish) {
    if (r.hasMatch(en) || r.hasMatch(enInAr)) return false;
  }
  for (final phrase in _forbiddenArabic) {
    if (ar.contains(phrase)) return false;
  }
  return true;
}

/// Guard 5. Both texts are non-empty and at most [maxExplanationLength]
/// characters.
bool passesLengthGuard(LocalizedText text) {
  for (final t in [text.ar.trim(), text.en.trim()]) {
    if (t.isEmpty || t.runes.length > maxExplanationLength) return false;
  }
  return true;
}

/// Runs all five guards. Empty means the explanation may be shown.
List<ExplanationIssue> checkExplanation(
  LocalizedText text, {
  required ExplanationProfile profile,
  required Iterable<Concept> courseConcepts,
  Iterable<Resource> courseResources = const [],
}) =>
    [
      if (!passesConceptGuard(text,
          profile: profile, courseConcepts: courseConcepts))
        ExplanationIssue.unknownConcept,
      if (!passesResourceGuard(text,
          profile: profile, courseResources: courseResources))
        ExplanationIssue.unapprovedResource,
      if (!passesLanguageGuard(text)) ExplanationIssue.wrongLanguage,
      if (!passesWordingGuard(text)) ExplanationIssue.forbiddenWording,
      if (!passesLengthGuard(text)) ExplanationIssue.tooLong,
    ];

// --------------------------------------------------------------- template

String _joinAr(List<String> names) => switch (names.length) {
      0 => '',
      1 => names[0],
      _ => '${names.sublist(0, names.length - 1).join('، ')} و${names.last}',
    };

String _joinEn(List<String> names) => switch (names.length) {
      0 => '',
      1 => names[0],
      _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
    };

/// At most three names per sentence keeps the text short.
const _maxNames = 3;

/// The deterministic explanation: 2–4 short, cautious sentences in both
/// languages, built only from the profile. Needs no network and passes all
/// guards (tested).
LocalizedText templateExplanation(ExplanationProfile profile) {
  List<ProfileConcept> inState(MasteryState s) =>
      profile.concepts.where((c) => c.state == s).toList();
  (String, String)? names(List<ProfileConcept> cs) {
    if (cs.isEmpty) return null;
    final shown = cs.take(_maxNames).toList();
    final more = cs.length > _maxNames;
    return (
      _joinAr([for (final c in shown) c.name.ar, if (more) 'غيرها']),
      _joinEn([for (final c in shown) c.name.en, if (more) 'others']),
    );
  }

  final ar = <String>[];
  final en = <String>[];

  final mastered = names(inState(MasteryState.demonstratedMastery));
  if (mastered != null) {
    ar.add('أظهرت فهمًا جيدًا لـ ${mastered.$1}.');
    en.add('You showed good understanding of ${mastered.$2}.');
  }

  final gap = profile.hints
      .where((h) => h.signal == PrerequisiteSignal.possibleContributingGap)
      .firstOrNull;
  final prereq = gap == null ? null : profile.concept(gap.prerequisiteId);
  final target = gap == null ? null : profile.concept(gap.conceptId);
  final difficult = inState(MasteryState.possibleDifficulty);
  if (prereq != null && target != null) {
    ar.add('قد يساعدك مراجعة ${prereq.name.ar} قبل ${target.name.ar}.');
    en.add('Reviewing ${prereq.name.en} before ${target.name.en} may help.');
  } else if (names(difficult) case final d?) {
    ar.add('قد يحتاج ${d.$1} إلى مراجعة.');
    en.add('${d.$2} may need review.');
  }

  final forming = names(inState(MasteryState.emerging));
  if (forming != null) {
    ar.add(
        'فهمك لـ ${forming.$1} في طور التكوّن، وقد يساعدك التدريب على تثبيته.');
    en.add(
      'Your understanding of ${forming.$2} is still forming, and practice may help.',
    );
  }

  final unknown = names(inState(MasteryState.insufficientEvidence));
  if (ar.length < 3 && unknown != null) {
    ar.add('لا توجد أدلة كافية بعد عن ${unknown.$1}.');
    en.add('There is not enough evidence yet about ${unknown.$2}.');
  }

  if (ar.isEmpty) {
    ar.add('لا توجد أدلة كافية بعد لتقديم ملاحظات مفصّلة.');
    en.add('There is not enough evidence yet for detailed feedback.');
  }
  // Keep at most three sentences, then the closing one (2–4 in total).
  while (ar.length > 3) {
    ar.removeLast();
    en.removeLast();
  }
  const closingAr = 'الخطوات التالية اقتراحات قد تساعدك.';
  const closingEn = 'The next steps are suggestions that may help you.';
  String build(List<String> s, String closing) => [...s, closing].join(' ');
  while (ar.length > 1 &&
      (build(ar, closingAr).length > maxExplanationLength ||
          build(en, closingEn).length > maxExplanationLength)) {
    ar.removeLast();
    en.removeLast();
  }
  return LocalizedText(ar: build(ar, closingAr), en: build(en, closingEn));
}

// ---------------------------------------------------------------- results

/// The explanation chosen for one profile.
class ExplanationOutcome {
  const ExplanationOutcome({
    required this.text,
    required this.fromAi,
    this.issues = const [],
  });

  final LocalizedText text;

  /// True when the model's text passed every guard.
  final bool fromAi;

  /// Why the model's text was not used (empty when [fromAi], or when no
  /// model answer was asked for).
  final List<ExplanationIssue> issues;
}

/// Explanations for all profiles of a session.
class ExplanationBatch {
  const ExplanationBatch(this.byProfile);

  final Map<String, ExplanationOutcome> byProfile;

  int get aiCount => byProfile.values.where((o) => o.fromAi).length;
  int get templateCount => byProfile.length - aiCount;

  /// How often each guard (or a missing answer) replaced a model text:
  /// evidence of AI explanation quality, like the AI draft statistics.
  Map<ExplanationIssue, int> get issueCounts {
    final out = <ExplanationIssue, int>{};
    for (final o in byProfile.values) {
      for (final i in o.issues) {
        out.update(i, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    return out;
  }
}

/// Picks every profile's explanation. With no [modelAnswer] (AI off, or the
/// request failed) every profile gets [templateExplanation]. Otherwise each
/// profile gets the model's text if it passes [checkExplanation], else the
/// template. Unknown profile IDs in the answer are ignored; for a repeated
/// ID the first entry counts.
ExplanationBatch resolveExplanations({
  required List<ExplanationProfile> profiles,
  String? modelAnswer,
  required Iterable<Concept> courseConcepts,
  Iterable<Resource> courseResources = const [],
}) {
  if (modelAnswer == null) {
    return ExplanationBatch({
      for (final p in profiles)
        p.id: ExplanationOutcome(
          text: templateExplanation(p),
          fromAi: false,
        ),
    });
  }
  final entries = _parseAnswer(modelAnswer);
  return ExplanationBatch({
    for (final p in profiles)
      p.id: () {
        if (entries == null) {
          return ExplanationOutcome(
            text: templateExplanation(p),
            fromAi: false,
            issues: const [ExplanationIssue.invalidAnswer],
          );
        }
        final text = entries[p.id];
        if (text == null) {
          return ExplanationOutcome(
            text: templateExplanation(p),
            fromAi: false,
            issues: const [ExplanationIssue.missing],
          );
        }
        final issues = checkExplanation(
          text,
          profile: p,
          courseConcepts: courseConcepts,
          courseResources: courseResources,
        );
        return issues.isEmpty
            ? ExplanationOutcome(text: text, fromAi: true)
            : ExplanationOutcome(
                text: templateExplanation(p),
                fromAi: false,
                issues: issues,
              );
      }(),
  });
}

/// profile ID → text, or null if the answer is not the expected JSON.
Map<String, LocalizedText>? _parseAnswer(String modelAnswer) {
  final Object? decoded;
  try {
    decoded = jsonDecode(stripCodeFence(modelAnswer));
  } on FormatException {
    return null;
  }
  final list = switch (decoded) {
    {'explanations': final List<Object?> l} => l,
    final List<Object?> l => l,
    _ => null,
  };
  if (list == null) return null;
  final out = <String, LocalizedText>{};
  for (final e in list) {
    if (e is! Map) continue;
    final id = e['profile_id'];
    final ar = e['text_ar'];
    final en = e['text_en'];
    if (id is! String || ar is! String || en is! String) continue;
    out.putIfAbsent(
      id.trim(),
      () => LocalizedText(ar: ar.trim(), en: en.trim()),
    );
  }
  return out;
}
