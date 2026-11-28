import 'dart:convert';

import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/services.dart';

import 'repositories/profile_repository.dart';

/// The career datasets bundled with the app (`assets/careers/`). Each one
/// names its source; a team draft says so on screen.
const careerRoleAssets = [
  'assets/careers/database_developer.json',
  'assets/careers/data_analyst.json',
];

Future<List<CareerRole>> loadCareerRoles(AssetBundle bundle) async => [
      for (final path in careerRoleAssets)
        careerRoleFromJson(
          jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>,
        ),
    ];

/// The student's concept standings from their saved sessions (oldest
/// first, as [ProfileRepository.sessions] returns them).
Map<String, ConceptStanding> standingsFromSessions(
        List<SavedSession> sessions) =>
    latestStandings([
      for (final s in sessions)
        [
          for (final c in s.concepts)
            ConceptStanding(
              conceptId: c.conceptId,
              state: c.state,
              attempts: c.attempts,
              correct: c.correct,
            ),
        ],
    ]);
