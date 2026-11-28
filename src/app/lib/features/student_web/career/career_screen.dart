import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/careers.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/text_direction.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../feedback/feedback_screen.dart' show stateLabel;
import 'external_course_screen.dart';

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
                if (_roleIndex == _otherRole) {
                  return _OtherRoleView(
                    roles: roles,
                    onSelect: (i) => setState(() => _roleIndex = i),
                  );
                }
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

/// "Another job": not one of the datasets.
const _otherRole = -1;

class _RoleChips extends StatelessWidget {
  const _RoleChips({
    required this.roles,
    required this.selected,
    required this.onSelect,
  });

  final List<CareerRole> roles;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    return Wrap(
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
        ChoiceChip(
          key: const ValueKey('role-other'),
          label: Text(l.studentCareerOtherRole),
          selected: selected == _otherRole,
          onSelected: (_) => onSelect(_otherRole),
        ),
      ],
    );
  }
}

/// The student wants a job Bousla has no skills list for yet: they write
/// it, and are told plainly that there is no data for it. Nothing is saved
/// or sent (front end only).
class _OtherRoleView extends StatefulWidget {
  const _OtherRoleView({required this.roles, required this.onSelect});

  final List<CareerRole> roles;
  final ValueChanged<int> onSelect;

  @override
  State<_OtherRoleView> createState() => _OtherRoleViewState();
}

class _OtherRoleViewState extends State<_OtherRoleView> {
  final _job = TextEditingController();
  var _sent = false;

  @override
  void dispose() {
    _job.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.studentCareerChooseRole, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _RoleChips(
              roles: widget.roles,
              selected: _otherRole,
              onSelect: widget.onSelect,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('other-role-field'),
              controller: _job,
              textDirection: textDirectionOf(_job.text),
              onChanged: (_) => setState(() => _sent = false),
              decoration: InputDecoration(
                labelText: l.studentCareerOtherRoleLabel,
                hintText: l.studentCareerOtherRoleHint,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const ValueKey('other-role-go'),
                onPressed: _job.text.trim().isEmpty
                    ? null
                    : () => setState(() => _sent = true),
                child: Text(l.studentCareerOtherRoleGo),
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: 16),
              Card(
                key: const ValueKey('other-role-none'),
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l.studentCareerOtherRoleNone(_job.text.trim()),
                    style: TextStyle(
                        color: theme.colorScheme.onTertiaryContainer),
                  ),
                ),
              ),
            ],
          ],
        ),
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
            _RoleChips(roles: roles, selected: selected, onSelect: onSelect),
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
            if (essential.isNotEmpty) ...[
              const SizedBox(height: 20),
              _EssentialSection(
                skills: essential,
                names: names,
                localAdverts: report.role.localAdverts,
              ),
            ],
            for (final (title, list, isEssential) in [
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
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(l.studentExternalOpen),
                subtitle: Text(l.studentCareerNextBody),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ExternalCourseScreen(),
                  ),
                ),
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
    // Folded by default; the adverts are already in [report] (loaded once
    // with the datasets), so opening or closing reads nothing again.
    return Card(
      key: const ValueKey('career-local'),
      child: ExpansionTile(
        key: const PageStorageKey('career-local-section'),
        shape: const Border(),
        tilePadding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
        leading:
            Icon(Icons.storefront_outlined, color: theme.colorScheme.primary),
        title: Text(l.studentCareerLocalTitle,
            style: theme.textTheme.titleSmall),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
        // Its own saved open/closed state, separate from the section it
        // sits in.
        key: PageStorageKey<Key?>(key),
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
    final (icon, color, label) = _statusLook(context, result.status);
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

/// Icon, colour and words for one engine [SkillStatus]: the skill card's
/// badge and the group headers use the same ones.
(IconData, Color, String) _statusLook(BuildContext context, SkillStatus status) {
  final l = AppLocalizations.of(context);
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
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
}

/// "Essential skills", folded by default. Inside, the skills are grouped by
/// the status the engine already gave them (`careerGaps`, unchanged), in the
/// order of [SkillStatus]; a group with no skill is not shown. Skills no
/// Bousla concept covers stay in their own folded list, as before.
class _EssentialSection extends StatelessWidget {
  const _EssentialSection({
    required this.skills,
    required this.names,
    this.localAdverts,
  });

  final List<SkillResult> skills;
  final Map<String, LocalizedText> names;
  final LocalAdverts? localAdverts;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ExpansionTile(
      key: const PageStorageKey('career-essential-section'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(l.studentCareerEssential, style: theme.textTheme.titleMedium),
      // How much of this list Bousla can say anything about.
      subtitle: Text(
        l.studentCareerCoverage(
          skills.where((s) => s.status != SkillStatus.outsideBousla).length,
          skills.length,
        ),
        key: const ValueKey('coverage-essential'),
        style: theme.textTheme.bodySmall,
      ),
      children: [
        for (final status in SkillStatus.values)
          if (status != SkillStatus.outsideBousla)
            if (skills.where((s) => s.status == status).toList()
                case final group when group.isNotEmpty)
              _StatusGroup(
                key: ValueKey('skill-group-${status.name}'),
                status: status,
                children: [
                  for (final s in group)
                    _SkillCard(
                        result: s, names: names, localAdverts: localAdverts),
                ],
              ),
        _OutsideList(
          key: const ValueKey('outside-essential'),
          skills: [
            for (final s in skills)
              if (s.status == SkillStatus.outsideBousla) s.skill,
          ],
        ),
      ],
    );
  }
}

/// One status heading (icon + words + count, never colour alone) and its
/// skill cards.
class _StatusGroup extends StatelessWidget {
  const _StatusGroup({
    super.key,
    required this.status,
    required this.children,
  });

  final SkillStatus status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (icon, color, label) = _statusLook(context, status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l.studentCareerStatusGroup(label, children.length),
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}
