import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/careers.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../feedback/feedback_screen.dart' show stateLabel;

/// Career path, preview (project scope 12). From the student's own profile:
/// the skills a chosen job asks for, and what the saved sessions show for
/// each (engine `careerGaps`, no AI). Only for a student with at least one
/// saved session. The skill lists are a team draft until a labour-market
/// source replaces them, and the screen says so.
class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key, required this.sessions, this.roles});

  /// The student's saved sessions, oldest first.
  final List<SavedSession> sessions;

  /// Tests pass roles directly; otherwise the bundled datasets are loaded.
  final List<CareerRole>? roles;

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  Future<(List<CareerRole>, Map<String, LocalizedText>)>? _data;
  var _roleIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<CareerRole>, Map<String, LocalizedText>)> _load() async {
    final roles =
        widget.roles ?? await loadCareerRoles(DefaultAssetBundle.of(context));
    // Concept names: from the saved sessions, then the courses' concepts
    // (for concepts the student was never asked about).
    final names = <String, LocalizedText>{
      for (final s in widget.sessions)
        for (final c in s.concepts) c.conceptId: c.name,
    };
    if (!mounted) return (roles, names);
    final content = ServicesScope.of(context).content;
    for (final courseId in {for (final s in widget.sessions) s.courseId}) {
      try {
        for (final c in await content.listConcepts(courseId)) {
          names.putIfAbsent(c.id, () => c.name);
        }
      } catch (_) {
        // Names fall back to the concept ID.
      }
    }
    // Last resort: the names the datasets carry.
    for (final r in roles) {
      r.conceptNames.forEach((id, n) => names.putIfAbsent(id, () => n));
    }
    return (roles, names);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentCareerTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: widget.sessions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.studentCareerNeedSession,
                    textAlign: TextAlign.center),
              ),
            )
          : FutureBuilder(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text(l.errorGeneric));
                }
                final data = snapshot.data;
                if (data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final (roles, names) = data;
                if (roles.isEmpty) return Center(child: Text(l.errorGeneric));
                final role = roles[_roleIndex.clamp(0, roles.length - 1)];
                final report =
                    careerGaps(role, standingsFromSessions(widget.sessions));
                return _ReportView(
                  roles: roles,
                  selected: _roleIndex,
                  onSelect: (i) => setState(() => _roleIndex = i),
                  report: report,
                  names: names,
                );
              },
            ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({
    required this.roles,
    required this.selected,
    required this.onSelect,
    required this.report,
    required this.names,
  });

  final List<CareerRole> roles;
  final int selected;
  final ValueChanged<int> onSelect;
  final CareerGapReport report;
  final Map<String, LocalizedText> names;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lang = currentLanguage(context);
    final essential = report.skills.where((s) => s.skill.essential).toList();
    final optional = report.skills.where((s) => !s.skill.essential).toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.studentCareerChooseRole, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < roles.length; i++)
                  ChoiceChip(
                    key: ValueKey('role-${roles[i].id}'),
                    label: Text(roles[i].title.of(lang)),
                    selected: i == selected,
                    onSelected: (_) => onSelect(i),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Notice(
              key: ValueKey(report.role.source.isDraft
                  ? 'career-draft-notice'
                  : 'career-source-notice'),
              text: report.role.source.isDraft
                  ? l.studentCareerDraftNotice
                  : l.studentCareerEscoNotice,
            ),
            if (!report.role.source.isDraft) ...[
              const SizedBox(height: 8),
              Text(
                key: const ValueKey('career-source'),
                _sourceLine(l, report.role.source),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(l.studentCareerEstimateNote, style: theme.textTheme.bodySmall),
            if (report.role.localAdverts != null) ...[
              const SizedBox(height: 16),
              _LocalMarketCard(report: report),
            ],
            for (final (title, list, isEssential) in [
              (l.studentCareerEssential, essential, true),
              (l.studentCareerOptional, optional, false),
            ])
              if (list.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                // How much of this list Bousla can say anything about.
                Text(
                  l.studentCareerCoverage(
                    list.where((s) => s.status != SkillStatus.outsideBousla).length,
                    list.length,
                  ),
                  key: ValueKey('coverage-${isEssential ? 'essential' : 'optional'}'),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final s in list)
                  if (s.status != SkillStatus.outsideBousla)
                    _SkillCard(
                        result: s,
                        names: names,
                        localAdverts: report.role.localAdverts),
                _OutsideList(
                  key: ValueKey('outside-${isEssential ? 'essential' : 'optional'}'),
                  skills: [
                    for (final s in list)
                      if (s.status == SkillStatus.outsideBousla) s.skill,
                  ],
                ),
              ],
            const SizedBox(height: 24),
            Card(
              key: const ValueKey('career-next'),
              child: ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(l.studentCareerNextTitle),
                subtitle: Text(l.studentCareerNextBody),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short source line in the screen's language; the dataset keeps the full
/// citation (`source.name`).
String _sourceLine(AppLocalizations l, CareerDataSource src) {
  if (src.kind != CareerSourceKind.esco) return l.studentCareerSource(src.name);
  // The ISO date as stored: same digits in both languages, with the year.
  return l.studentCareerSourceEsco(src.retrieved ?? '');
}

/// What local job adverts asked for most, and whether Bousla measures it.
/// Only with enough adverts; otherwise says how many there are so far.
class _LocalMarketCard extends StatelessWidget {
  const _LocalMarketCard({required this.report});

  final CareerGapReport report;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lang = currentLanguage(context);
    final local = report.role.localAdverts!;
    final covered = {
      for (final s in report.skills)
        if (s.status != SkillStatus.outsideBousla) s.skill.id,
    };
    return Card(
      key: const ValueKey('career-local'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l.studentCareerLocalTitle,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!local.enough)
              Text(
                l.studentCareerLocalTooFew(local.total, minLocalAdverts),
                key: const ValueKey('career-local-too-few'),
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Text(
                l.studentCareerLocalIntro(local.total, local.sites.join('، '),
                    local.publishedFrom, local.publishedTo),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final s in report.role.topLocalSkills())
                Padding(
                  key: ValueKey('local-top-${s.id}'),
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        covered.contains(s.id)
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        size: 18,
                        color: covered.contains(s.id)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.name.of(lang)}: '
                          '${l.studentCareerLocalCount(s.localCount!, local.total)} · '
                          '${covered.contains(s.id) ? l.studentCareerLocalCovered : l.studentCareerLocalNotCovered}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              if (local.labellers < 2) ...[
                const SizedBox(height: 10),
                Text(l.studentCareerLocalOneLabeller,
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: scheme.onTertiaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: scheme.onTertiaryContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The skills no Bousla concept covers yet: one folded list, not a card
/// each (they carry no evidence, only the name).
class _OutsideList extends StatelessWidget {
  const _OutsideList({super.key, required this.skills});

  final List<CareerSkill> skills;

  @override
  Widget build(BuildContext context) {
    if (skills.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lang = currentLanguage(context);
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        leading: Icon(Icons.remove_circle_outline,
            color: theme.colorScheme.outline),
        title: Text(l.studentCareerOutsideCount(skills.length),
            style: theme.textTheme.titleSmall),
        subtitle: Text(l.studentCareerOutsideHint,
            style: theme.textTheme.bodySmall),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in skills)
                Chip(
                  key: ValueKey('outside-skill-${s.id}'),
                  label: Text(s.name.of(lang)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.result,
    required this.names,
    this.localAdverts,
  });

  final SkillResult result;
  final Map<String, LocalizedText> names;
  final LocalAdverts? localAdverts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lang = currentLanguage(context);
    final scheme = theme.colorScheme;
    final (icon, color, label) = switch (result.status) {
      SkillStatus.possibleGap => (
          Icons.error_outline,
          scheme.error,
          l.studentCareerStatusGap
        ),
      SkillStatus.noEvidence => (
          Icons.help_outline,
          scheme.onSurfaceVariant,
          l.studentCareerStatusNoEvidence
        ),
      SkillStatus.partial => (
          Icons.timelapse,
          scheme.tertiary,
          l.studentCareerStatusPartial
        ),
      SkillStatus.evidence => (
          Icons.check_circle_outline,
          scheme.primary,
          l.studentCareerStatusEvidence
        ),
      SkillStatus.outsideBousla => (
          Icons.remove_circle_outline,
          scheme.outline,
          l.studentCareerStatusOutside
        ),
    };
    String name(String id) => names[id]?.of(lang) ?? id;
    final standing = {for (final c in result.concepts) c.conceptId: c};
    return Card(
      key: ValueKey('skill-${result.skill.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(result.skill.name.of(lang),
                      style: theme.textTheme.titleSmall),
                ),
                const SizedBox(width: 8),
                // Icon + word: never colour alone.
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style: theme.textTheme.labelMedium?.copyWith(color: color)),
              ],
            ),
            if (result.skill.localCount != null &&
                (result.skill.localCount ?? 0) > 0 &&
                localAdverts?.enough == true)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l.studentCareerLocalCount(
                      result.skill.localCount!, localAdverts!.total),
                  key: ValueKey('local-count-${result.skill.id}'),
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            if (result.status == SkillStatus.outsideBousla)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.studentCareerOutsideHint,
                    style: theme.textTheme.bodySmall),
              )
            else ...[
              const SizedBox(height: 6),
              for (final id in result.skill.conceptIds)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    standing[id] == null || !standing[id]!.assessed
                        ? '${name(id)}: ${l.studentCareerNotAssessed}'
                        : '${name(id)}: ${stateLabel(l, standing[id]!.state)} · '
                            '${l.studentFeedbackEvidence(standing[id]!.correct, standing[id]!.attempts)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (result.toWorkOn.isNotEmpty &&
                  result.status != SkillStatus.evidence)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l.studentCareerStartWith(
                        result.toWorkOn.map(name).join(lang == Language.ar ? '، ' : ', ')),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
