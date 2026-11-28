import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/repositories/auth_service.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/language.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../career/career_screen.dart';
import '../feedback/feedback_screen.dart' show stateLabel;
import '../knowledge_map/knowledge_map_screen.dart';
import '../../../shared/widgets/bousla_mark.dart';

/// "My profile": the student's own saved sessions (architecture §10).
/// Progress per concept across sessions, the sessions themselves (each can
/// be removed), delete everything, sign out. Only this student can read it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<SavedSession>>? _sessions;
  StudentAccount? _account;
  final _progressKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _account ??= ServicesScope.of(context).auth.studentAccount;
    _sessions ??= _load();
  }

  Future<List<SavedSession>> _load() async {
    final account = _account;
    if (account == null) return const [];
    return ServicesScope.of(context).profiles.sessions(account.uid);
  }

  // A block body: setState must not get a Future back.
  void _reload() => setState(() {
        _sessions = _load();
      });

  Future<void> _remove(SavedSession s) async {
    await ServicesScope.of(context)
        .profiles
        .removeSession(_account!.uid, s.code);
    if (mounted) _reload();
  }

  Future<void> _deleteAll() async {
    final l = AppLocalizations.of(context);
    final services = ServicesScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.studentProfileDeleteTitle),
        content: Text(l.studentProfileDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.studentProfileCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.studentProfileDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await services.profiles.delete(_account!.uid);
    messenger.showSnackBar(SnackBar(content: Text(l.studentProfileDeleted)));
    navigator.pop();
  }

  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    await ServicesScope.of(context).auth.signOut();
    navigator.pop();
  }

  void _join() => Navigator.of(context).pushNamed('/join');

  Future<void> _showMap(List<SavedSession> sessions) async {
    final l = AppLocalizations.of(context);
    final lang = currentLanguage(context);
    final services = ServicesScope.of(context);
    final navigator = Navigator.of(context);
    final uid = _account?.uid;
    if (uid == null) return;
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.studentDashboardMap),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(sessions.isEmpty
                  ? l.studentDashboardEmpty
                  : l.studentDashboardChooseSession),
              for (final session in sessions.reversed)
                ListTile(
                  title: Text(_sessionName(l, session, lang)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(session.code),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.studentProfileCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(l.homeJoin),
          ),
        ],
      ),
    );
    if (!mounted || code == null) return;
    if (code.isEmpty) {
      _join();
      return;
    }
    try {
      final feedback = await services.sessions
          .watchMyFeedback(code, uid)
          .first
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (feedback != null) {
        await navigator.push(MaterialPageRoute<void>(
          builder: (_) => KnowledgeMapScreen(feedback: feedback),
        ));
        return;
      }
    } catch (_) {
      // A transferred session may not have feedback under this account UID.
      // Never guess a graph from the saved summary.
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.studentDashboardMap),
        content: Text(l.studentDashboardMapUnavailable),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.studentProfileCancel),
          ),
        ],
      ),
    );
  }

  Widget _dashboard(List<SavedSession> sessions) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.explore_outlined,
            size: 52, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(l.studentDashboardTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Text(l.studentDashboardSubtitle,
            textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('dashboard-join'),
          onPressed: _join,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l.homeJoin),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final map = _dashboardTile(
            key: const ValueKey('dashboard-map'),
            icon: Icons.account_tree_outlined,
            title: l.studentDashboardMap,
            subtitle: l.studentDashboardMapHint,
            onTap: () => _showMap(sessions),
          );
          final progress = _dashboardTile(
            key: const ValueKey('dashboard-progress'),
            icon: Icons.show_chart,
            title: l.studentDashboardProgress,
            subtitle: l.studentDashboardProgressHint,
            onTap: () {
              final target = _progressKey.currentContext;
              if (target != null) {
                Scrollable.ensureVisible(target,
                    duration: const Duration(milliseconds: 300));
              }
            },
          );
          if (constraints.maxWidth < 500) {
            return Column(children: [map, progress]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: map),
            const SizedBox(width: 8),
            Expanded(child: progress),
          ]);
        }),
        _dashboardTile(
          key: const ValueKey('open-career'),
          icon: Icons.work_outline,
          title: l.studentDashboardCareer,
          subtitle: l.studentDashboardCareerHint,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CareerScreen(sessions: sessions),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          key: const ValueKey('dashboard-instructor'),
          onPressed: () => Navigator.of(context).pushNamed('/instructor'),
          icon: const Icon(Icons.school_outlined),
          label: Text(l.homeInstructor),
        ),
      ],
    );
  }

  Widget _dashboardTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      Card(
        key: key,
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final lang = currentLanguage(context);
    final account = _account;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentProfileTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: WatermarkedBody(
        alignment: Alignment(0, 0.7),
        child: account == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child:
                      Text(l.studentProfileNone, textAlign: TextAlign.center),
                ),
              )
            : FutureBuilder<List<SavedSession>>(
                future: _sessions,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text(l.errorGeneric));
                  }
                  final sessions = snapshot.data;
                  if (sessions == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final progress = _progressByConcept(sessions);
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _dashboard(sessions),
                            const Divider(),
                            const SizedBox(height: 16),
                            Text(
                              l.studentProfileSignedInAs(account.label),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l.studentProfileProgressTitle,
                              key: _progressKey,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.studentProfileProgressNote,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            if (sessions.isEmpty) Text(l.studentProfileEmpty),
                            for (final entry in progress)
                              Card(
                                key: ValueKey('progress-${entry.$1}'),
                                child: ListTile(
                                  title: Text(entry.$2.first.$2.name.of(lang)),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (final (session, concept) in entry.$2)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            '${_sessionName(l, session, lang)}: '
                                            '${stateLabel(l, concept.state)} · '
                                            '${l.studentFeedbackEvidence(concept.correct, concept.attempts)}',
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            const SizedBox(height: 24),
                            Text(
                              l.studentProfileSessionsTitle,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            if (sessions.isEmpty) Text(l.studentProfileEmpty),
                            for (final s in sessions)
                              Card(
                                key: ValueKey('session-${s.code}'),
                                child: ListTile(
                                  title: Text(_sessionName(l, s, lang)),
                                  subtitle: s.addedAt == null
                                      ? null
                                      : Text(MaterialLocalizations.of(context)
                                          .formatMediumDate(
                                              s.addedAt!.toLocal())),
                                  trailing: IconButton(
                                    tooltip: l.studentProfileRemoveSession,
                                    icon:
                                        const Icon(Icons.remove_circle_outline),
                                    onPressed: () => _remove(s),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),
                            OutlinedButton.icon(
                              onPressed: _signOut,
                              icon: const Icon(Icons.logout),
                              label: Text(l.studentProfileSignOut),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                              onPressed: _deleteAll,
                              icon: const Icon(Icons.delete_forever_outlined),
                              label: Text(l.studentProfileDelete),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _sessionName(AppLocalizations l, SavedSession s, Language lang) {
  final t = s.title?.of(lang).trim();
  return t == null || t.isEmpty ? s.code : t;
}

/// Each concept with its result in every saved session, sessions oldest
/// first; concepts in the order they first appear. Only sessions where the
/// concept had questions count (no evidence is not a result).
List<(String, List<(SavedSession, SavedConcept)>)> _progressByConcept(
  List<SavedSession> sessions,
) {
  final byConcept = <String, List<(SavedSession, SavedConcept)>>{};
  for (final s in sessions) {
    for (final c in s.concepts) {
      if (c.attempts == 0) continue;
      (byConcept[c.conceptId] ??= []).add((s, c));
    }
  }
  return [for (final e in byConcept.entries) (e.key, e.value)];
}
