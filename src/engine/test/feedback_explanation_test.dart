import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final _resources = [
  Resource(
    id: 'res_pk_video',
    conceptIds: ['primary_key'],
    type: ResourceType.video,
    language: ResourceLanguage.both,
    title: t('شرح المفتاح الأساسي', 'Primary keys explained'),
    url: 'https://example.com/pk',
  ),
  Resource(
    id: 'res_rm_practice',
    conceptIds: ['relational_model'],
    type: ResourceType.activity,
    language: ResourceLanguage.both,
    title: t('تدريب: الجداول والصفوف', 'Practice: tables and rows'),
  ),
  Resource(
    id: 'res_fk_draft',
    conceptIds: ['foreign_key'],
    type: ResourceType.link,
    language: ResourceLanguage.en,
    title: t('مقال غير معتمد', 'Unreviewed article'),
    url: 'https://unreviewed.example.org/fk',
    status: ReviewStatus.pendingReview,
  ),
];

/// The whole engine for one participant, as the instructor app runs it.
ExplanationProfile _profileFor(List<Response> responses, String participant,
    {Language lang = Language.ar}) {
  final scored = scoreResponses(
          responses: responses, questions: testQuestions, keys: testKeys)
      .scored;
  final evidence = evidenceByParticipant(
      scored: scored, conceptIds: testConcepts.map((c) => c.id));
  final masteries = estimateAll(evidence[participant]!);
  final findings =
      analyzePrerequisites(masteries: masteries, concepts: testConcepts);
  final recs = recommend(
    masteries: masteries,
    concepts: testConcepts,
    resources: _resources,
    preferredLanguage: lang,
  );
  return buildExplanationProfile(
    masteries: masteries,
    findings: findings,
    recommendations: recs,
    concepts: testConcepts,
  );
}

/// relational_model: mastery; primary_key: difficulty; foreign_key: difficulty
/// → primary_key may be contributing to foreign_key.
List<Response> _struggling(String p, {Language lang = Language.ar}) => [
      ...answers(p, 'relational_model', 3, 3, lang: lang),
      ...answers(p, 'primary_key', 0, 3, lang: lang),
      ...answers(p, 'foreign_key', 1, 3, lang: lang),
    ];

/// Mastery everywhere.
List<Response> _strong(String p) => [
      ...answers(p, 'relational_model', 3, 3),
      ...answers(p, 'primary_key', 3, 3),
      ...answers(p, 'foreign_key', 3, 3),
    ];

final _profile =
    groupProfiles({'x': _profileFor(_struggling('s1'), 's1')}).profiles.single;

const _goodAr = 'أظهرت فهمًا جيدًا للنموذج العلائقي. '
    'قد يساعدك مراجعة المفتاح الأساسي (Primary Key) قبل المفتاح الخارجي. '
    'يمكنك البدء بـ "شرح المفتاح الأساسي".';
const _goodEn = 'You showed good understanding of the relational model. '
    'Reviewing primary keys before foreign keys may help. '
    'You could start with "Primary keys explained".';

LocalizedText _text({String ar = _goodAr, String en = _goodEn}) =>
    LocalizedText(ar: ar, en: en);

String _answer(List<Map<String, String>> entries) => jsonEncode(entries);

void main() {
  group('profiles', () {
    test('identical profiles are merged into one', () {
      final responses = [
        ..._struggling('s1'),
        ..._struggling('s2'),
        ..._strong('s3'),
      ];
      final groups = groupProfiles({
        for (final p in ['s1', 's2', 's3']) p: _profileFor(responses, p),
      });
      expect(groups.profiles, hasLength(2));
      expect(groups.profileIdOf['s1'], groups.profileIdOf['s2']);
      expect(groups.profileIdOf['s3'], isNot(groups.profileIdOf['s1']));
      expect(groups.profiles.map((p) => p.id), ['p1', 'p2']);
    });

    test('profile IDs do not depend on the order of students', () {
      final responses = [..._struggling('s1'), ..._strong('s2')];
      final a = groupProfiles({
        's1': _profileFor(responses, 's1'),
        's2': _profileFor(responses, 's2'),
      });
      final b = groupProfiles({
        's2': _profileFor(responses, 's2'),
        's1': _profileFor(responses, 's1'),
      });
      expect(a.profileIdOf, b.profileIdOf);
    });

    test('the prompt holds no UID, name or answer', () {
      const uid = 'Xy7Qk2LmP9anonUid';
      final responses = _struggling(uid);
      final groups = groupProfiles({uid: _profileFor(responses, uid)});
      final prompt = buildFeedbackExplanationPrompt(groups.profiles);
      expect(prompt, isNot(contains(uid)));
      final json = jsonEncode(groups.profiles.single.toPromptJson());
      expect(json, isNot(contains(uid)));
      // No option IDs, question IDs, counts or URLs either.
      expect(json, isNot(contains('selected')));
      expect(json, isNot(contains('primary_key_1')));
      expect(json, isNot(contains('attempts')));
      expect(json, isNot(contains('https://')));
      expect(
        groups.profiles.single.toPromptJson().keys,
        unorderedEquals([
          'profile_id',
          'concepts',
          'prerequisite_hints',
          'recommendations'
        ]),
      );
    });

    test('a profile carries the engine results and approved resources only',
        () {
      final p = _profile;
      expect(
        {for (final c in p.concepts) c.id: c.state},
        {
          'foreign_key': MasteryState.possibleDifficulty,
          'primary_key': MasteryState.possibleDifficulty,
          'relational_model': MasteryState.demonstratedMastery,
        },
      );
      expect(p.hints.single.prerequisiteId, 'primary_key');
      expect(p.hints.single.signal, PrerequisiteSignal.possibleContributingGap);
      expect(p.recommendations.first.conceptId, 'primary_key');
      expect(p.resources.map((r) => r.id), isNot(contains('res_fk_draft')));
      expect(p.resources.map((r) => r.id), contains('res_pk_video'));
    });

    test('Arabic and English answers give the same profile and explanation',
        () {
      final ar = _profileFor(_struggling('s1'), 's1', lang: Language.ar);
      final en = _profileFor(_struggling('s1', lang: Language.en), 's1',
          lang: Language.en);
      expect(ar.signature, en.signature);
      expect(templateExplanation(ar).ar, templateExplanation(en).ar);
      expect(templateExplanation(ar).en, templateExplanation(en).en);
    });

    test('one prompt covers every unique profile', () {
      final responses = [..._struggling('s1'), ..._strong('s2')];
      final groups = groupProfiles({
        's1': _profileFor(responses, 's1'),
        's2': _profileFor(responses, 's2'),
      });
      final prompt = buildFeedbackExplanationPrompt(groups.profiles);
      expect(prompt, contains('"profile_id": "p1"'));
      expect(prompt, contains('"profile_id": "p2"'));
      expect(feedbackExplanationJsonSchema()['type'], 'array');
    });
  });

  group('guard 1: concepts', () {
    test('passes for concepts in the profile, with Arabic prefixes', () {
      expect(
        passesConceptGuard(_text(),
            profile: _profile, courseConcepts: testConcepts),
        isTrue,
      );
      expect(
        passesConceptGuard(
          _text(ar: 'قد يفيدك الرجوع للمفتاح الأساسي وبالمفتاح الخارجي.'),
          profile: _profile,
          courseConcepts: testConcepts,
        ),
        isTrue,
      );
    });

    test('rejects a course concept that is not in the profile', () {
      final narrow = ExplanationProfile(
        concepts: [
          ProfileConcept(
            id: 'primary_key',
            name: t('المفتاح الأساسي', 'Primary Key'),
            state: MasteryState.emerging,
          ),
        ],
      );
      // English text names Foreign Key, which this student was not given.
      expect(
        passesConceptGuard(
          _text(
            ar: 'فهمك للمفتاح الأساسي في طور التكوّن.',
            en: 'Your understanding of primary keys and foreign keys is forming.',
          ),
          profile: narrow,
          courseConcepts: testConcepts,
        ),
        isFalse,
      );
      // Same in Arabic.
      expect(
        passesConceptGuard(
          _text(
            ar: 'راجع المفتاح الخارجي.',
            en: 'Your understanding of primary keys is forming.',
          ),
          profile: narrow,
          courseConcepts: testConcepts,
        ),
        isFalse,
      );
    });

    test('a shorter course concept inside an allowed name is not counted', () {
      final concepts = [
        ...testConcepts,
        Concept(id: 'key', name: t('المفتاح', 'Key')),
      ];
      expect(
        passesConceptGuard(_text(),
            profile: _profile, courseConcepts: concepts),
        isTrue,
      );
      expect(
        passesConceptGuard(
          _text(en: 'A key may need review.'),
          profile: _profile,
          courseConcepts: concepts,
        ),
        isFalse,
      );
    });

    test('rejects a concept ID that is not in the profile', () {
      final narrow = ExplanationProfile(concepts: [
        ProfileConcept(
          id: 'primary_key',
          name: t('المفتاح الأساسي', 'Primary Key'),
          state: MasteryState.emerging,
        ),
      ]);
      expect(
        passesConceptGuard(
          _text(
            ar: 'فهمك للمفتاح الأساسي في طور التكوّن.',
            en: 'Look at foreign_key next.',
          ),
          profile: narrow,
          courseConcepts: testConcepts,
        ),
        isFalse,
      );
    });
  });

  group('guard 2: resources', () {
    test('passes for profile resources by title, and their own URL', () {
      expect(passesResourceGuard(_text(), profile: _profile), isTrue);
      expect(
        passesResourceGuard(
          _text(en: 'See https://example.com/pk.'),
          profile: _profile,
        ),
        isTrue,
      );
    });

    test('rejects invented URLs and domains', () {
      for (final en in [
        'Watch https://youtube.com/watch?v=abc for help.',
        'See www.w3schools.com for more.',
        'Try khanacademy.org next.',
      ]) {
        expect(
          passesResourceGuard(_text(en: en), profile: _profile),
          isFalse,
          reason: en,
        );
      }
      expect(
        passesResourceGuard(
          _text(ar: 'راجع الموقع sqlzoo.net للتدريب على المفتاح الأساسي.'),
          profile: _profile,
        ),
        isFalse,
      );
    });

    test('rejects resources that are not approved for this student', () {
      expect(
        passesResourceGuard(
          _text(en: 'Read "Unreviewed article" about foreign keys.'),
          profile: _profile,
          courseResources: _resources,
        ),
        isFalse,
      );
      expect(
        passesResourceGuard(
          _text(en: 'Open res_fk_draft next.'),
          profile: _profile,
        ),
        isFalse,
      );
    });
  });

  group('guard 3: language', () {
    test('passes Arabic with English terms, and plain English', () {
      expect(passesLanguageGuard(_text()), isTrue);
    });

    test('rejects text_ar without Arabic and text_en with Arabic', () {
      expect(passesLanguageGuard(_text(ar: _goodEn)), isFalse);
      expect(passesLanguageGuard(_text(en: _goodAr)), isFalse);
      expect(
        passesLanguageGuard(_text(en: 'Review the المفتاح الأساسي first.')),
        isFalse,
      );
      // Mostly English with one Arabic word.
      expect(
        passesLanguageGuard(_text(ar: 'Review primary keys first, شكرا.')),
        isFalse,
      );
    });
  });

  group('guard 4: wording', () {
    test('passes cautious wording', () {
      expect(passesWordingGuard(_text()), isTrue);
      expect(
        passesWordingGuard(_text(
          ar: 'قد يحتاج المفتاح الخارجي إلى مراجعة، ولا توجد أدلة كافية بعد.',
          en: 'Foreign keys may need review; there is not enough evidence yet.',
        )),
        isTrue,
      );
    });

    test('rejects definitive or discouraging Arabic', () {
      for (final ar in [
        'لديك فجوة في المفتاح الأساسي.',
        'أنت لا تفهم المفتاح الخارجي.',
        'مستواك ضعيف في المفتاح الأساسي.',
        'لقد فشلت في هذا الجزء.',
        'بالتأكيد تحتاج إلى مراجعة المفتاح الأساسي.',
        'لديك فَجْوَةٌ واضحة.', // with diacritics
      ]) {
        expect(passesWordingGuard(_text(ar: ar)), isFalse, reason: ar);
      }
    });

    test('rejects definitive or discouraging English', () {
      for (final en in [
        'You have a gap in primary keys.',
        'You failed the foreign key questions.',
        "You don't understand foreign keys.",
        'Your knowledge of keys is weak.',
        'This clearly shows a deficiency.',
        'You Have A Gap.', // case
      ]) {
        expect(passesWordingGuard(_text(en: en)), isFalse, reason: en);
      }
    });
  });

  group('guard 5: length', () {
    test('passes up to 600 characters', () {
      expect(passesLengthGuard(_text()), isTrue);
      expect(
        passesLengthGuard(_text(en: 'a' * maxExplanationLength)),
        isTrue,
      );
    });

    test('rejects longer or empty text', () {
      expect(
        passesLengthGuard(_text(en: 'a' * (maxExplanationLength + 1))),
        isFalse,
      );
      expect(
        passesLengthGuard(_text(ar: 'ب' * (maxExplanationLength + 1))),
        isFalse,
      );
      expect(passesLengthGuard(_text(ar: '  ')), isFalse);
    });
  });

  test('a valid explanation passes all guards together', () {
    expect(
      checkExplanation(_text(),
          profile: _profile,
          courseConcepts: testConcepts,
          courseResources: _resources),
      isEmpty,
    );
  });

  group('template', () {
    // Every combination of states for the three test concepts.
    final cases = <ExplanationProfile>[];
    for (final a in MasteryState.values) {
      for (final b in MasteryState.values) {
        for (final c in MasteryState.values) {
          cases.add(ExplanationProfile(concepts: [
            ProfileConcept(
                id: 'foreign_key', name: testConcepts[2].name, state: a),
            ProfileConcept(
                id: 'primary_key', name: testConcepts[1].name, state: b),
            ProfileConcept(
                id: 'relational_model', name: testConcepts[0].name, state: c),
          ], hints: [
            if (a == MasteryState.possibleDifficulty &&
                b == MasteryState.possibleDifficulty)
              const ProfileHint(
                conceptId: 'foreign_key',
                prerequisiteId: 'primary_key',
                signal: PrerequisiteSignal.possibleContributingGap,
              ),
          ]));
        }
      }
    }

    int sentences(String s) => RegExp(r'[.!?؟]').allMatches(s).length;

    test('passes every guard in both languages, for every state mix', () {
      for (final p in [...cases, const ExplanationProfile(concepts: [])]) {
        final text = templateExplanation(p);
        expect(
          checkExplanation(text,
              profile: p,
              courseConcepts: testConcepts,
              courseResources: _resources),
          isEmpty,
          reason: '${text.ar}\n${text.en}',
        );
        expect(sentences(text.ar), inInclusiveRange(2, 4), reason: text.ar);
        expect(sentences(text.en), inInclusiveRange(2, 4), reason: text.en);
      }
    });

    test('names a possible prerequisite cautiously', () {
      final text = templateExplanation(_profile);
      expect(text.ar,
          contains('قد يساعدك مراجعة المفتاح الأساسي قبل المفتاح الخارجي.'));
      expect(text.ar, contains('أظهرت فهمًا جيدًا لـ النموذج العلائقي.'));
      expect(text.en,
          contains('Reviewing Primary Key before Foreign Key may help.'));
    });

    test('passes the guards on the real course concepts with long lists', () {
      final names = [
        ('relational_model', t('النموذج العلائقي', 'Relational Model')),
        (
          'er_modeling',
          t('نمذجة الكيانات والعلاقات', 'Entity-Relationship Modeling')
        ),
        (
          'functional_dependency',
          t('الاعتمادية الوظيفية', 'Functional Dependency')
        ),
        ('normalization', t('التطبيع', 'Normalization')),
        ('sql_select', t('استعلامات SELECT الأساسية', 'Basic SELECT Queries')),
        ('sql_join', t('ربط الجداول (JOIN)', 'Joins')),
        ('sql_aggregation', t('التجميع (GROUP BY)', 'Aggregation (GROUP BY)')),
        (
          'transactions_acid',
          t('المعاملات وخصائص ACID', 'Transactions and ACID')
        ),
      ];
      final course = [
        for (final (id, name) in names) Concept(id: id, name: name),
      ];
      for (final state in MasteryState.values) {
        final p = ExplanationProfile(concepts: [
          for (final (id, name) in names)
            ProfileConcept(id: id, name: name, state: state),
        ]);
        final text = templateExplanation(p);
        expect(
            checkExplanation(text, profile: p, courseConcepts: course), isEmpty,
            reason: text.en);
      }
    });
  });

  group('resolveExplanations', () {
    final responses = [
      ..._struggling('s1'),
      ..._struggling('s2'),
      ..._strong('s3'),
    ];
    final groups = groupProfiles({
      for (final p in ['s1', 's2', 's3']) p: _profileFor(responses, p),
    });
    final struggling = groups.profileIdOf['s1']!;
    final strong = groups.profileIdOf['s3']!;

    test('no model answer: every profile gets the template', () {
      final batch = resolveExplanations(
          profiles: groups.profiles, courseConcepts: testConcepts);
      expect(batch.aiCount, 0);
      expect(batch.templateCount, 2);
      expect(batch.byProfile[struggling]!.text.ar,
          templateExplanation(groups.profileOf('s1')).ar);
    });

    test('an invalid answer falls back to the template for all', () {
      final batch = resolveExplanations(
        profiles: groups.profiles,
        modelAnswer: 'Sorry, I cannot help with that.',
        courseConcepts: testConcepts,
      );
      expect(batch.aiCount, 0);
      expect(batch.issueCounts[ExplanationIssue.invalidAnswer], 2);
    });

    test('valid entries are used; a failing or missing one is replaced', () {
      final batch = resolveExplanations(
        profiles: groups.profiles,
        modelAnswer: '```json\n${_answer([
              {
                'profile_id': struggling,
                'text_ar': _goodAr,
                'text_en': _goodEn
              },
              {
                'profile_id': strong,
                'text_ar': 'لقد فشلت.',
                'text_en': 'You failed.',
              },
              {'profile_id': 'p99', 'text_ar': 'x', 'text_en': 'y'},
            ])}\n```',
        courseConcepts: testConcepts,
        courseResources: _resources,
      );
      expect(batch.byProfile[struggling]!.fromAi, isTrue);
      expect(batch.byProfile[struggling]!.text.en, _goodEn);
      expect(batch.byProfile[strong]!.fromAi, isFalse);
      expect(batch.byProfile[strong]!.issues,
          contains(ExplanationIssue.forbiddenWording));
      expect(batch.byProfile[strong]!.text.en,
          templateExplanation(groups.profileOf('s3')).en);
      expect(batch.byProfile.keys, isNot(contains('p99')));

      final missing = resolveExplanations(
        profiles: groups.profiles,
        modelAnswer: _answer([
          {'profile_id': struggling, 'text_ar': _goodAr, 'text_en': _goodEn},
        ]),
        courseConcepts: testConcepts,
      );
      expect(missing.byProfile[strong]!.issues, [ExplanationIssue.missing]);
    });

    test('every student gets the explanation of their own profile', () {
      final batch = resolveExplanations(
        profiles: groups.profiles,
        modelAnswer: _answer([
          {'profile_id': struggling, 'text_ar': _goodAr, 'text_en': _goodEn},
        ]),
        courseConcepts: testConcepts,
      );
      String textOf(String student) =>
          batch.byProfile[groups.profileIdOf[student]]!.text.en;
      expect(textOf('s1'), _goodEn);
      expect(textOf('s2'), _goodEn);
      expect(textOf('s3'), templateExplanation(groups.profileOf('s3')).en);
    });
  });
}
