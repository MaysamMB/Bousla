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
import 'consent_dialog.dart';
import 'profile_avatar.dart';

/// "My profile": the student's own saved sessions (architecture §10).
/// A header with the student's own name and preset picture, a dashboard
/// (join a session, knowledge map, progress, career path), then each saved
/// session with its own results (each can be removed), delete everything,
/// sign out. Only this student can read it.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<List<SavedSession>>? _sessions;
  StudentAccount? _account;
  var _info = const ProfileInfo();

  /// "My sessions", where the dashboard's progress tile scrolls to.
  final _progressKey = GlobalKey();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_account == null) {
      _account = ServicesScope.of(context).auth.studentAccount;
      _loadInfo();
    }
    _sessions ??= _load();
  }

  var _signingIn = false;

  /// "Sign in with Google" when this browser has no profile: links this
  /// browser to Google (keeping its answers), or signs in to the account's
  /// existing profile from another browser. A new profile needs consent.
  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    final services = ServicesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      StudentAccount account;
      try {
        await services.auth.ensureParticipant();
        account = await services.auth.linkStudentAccount();
      } on StudentLinkFailure catch (e) {
        if (e.problem != StudentLinkProblem.accountInUse) rethrow;
        account = await services.auth.switchToLinkedStudentAccount();
      }
      final consented = await services.profiles.consentVersion(account.uid);
      if (consented == null || consented < profileConsentVersion) {
        if (!mounted) return;
        // No spinner while the student reads the consent text.
        setState(() => _signingIn = false);
        if (await showProfileConsent(context) != true) {
          messenger.showSnackBar(
              SnackBar(content: Text(l.studentProfileSignInNoConsent)));
          return;
        }
        await services.profiles.create(account.uid);
      }
      if (!mounted) return;
      setState(() {
        _account = account;
        _sessions = _load();
      });
      _loadInfo();
    } on StudentLinkFailure catch (e) {
      debugPrint('Profile sign-in failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text(switch (e.problem) {
          // Safari: the window must open straight from a tap.
          StudentLinkProblem.popupBlocked => l.studentProfileSignInTapAgain,
          StudentLinkProblem.cancelled => l.studentProfileErrCancelled,
          StudentLinkProblem.network => l.studentProfileErrNetwork,
          StudentLinkProblem.notEnabled => l.studentProfileErrNotEnabled,
          StudentLinkProblem.instructorSignedIn =>
            l.studentProfileErrInstructor,
          _ => '${l.studentProfileErrFailed} (${e.detail ?? e.problem.name})',
        }),
      ));
    } catch (e) {
      debugPrint('Profile sign-in failed: $e');
      messenger.showSnackBar(
          SnackBar(content: Text('${l.studentProfileErrFailed} ($e)')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _loadInfo() async {
    final account = _account;
    if (account == null) return;
    try {
      final info = await ServicesScope.of(context).profiles.info(account.uid);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      // Shown without a name; the sessions still load.
      debugPrint('Loading the profile name failed: $e');
    }
  }

  Future<void> _editInfo() async {
    final l = AppLocalizations.of(context);
    final services = ServicesScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final edited = await showDialog<ProfileInfo>(
      context: context,
      builder: (_) => _EditInfoDialog(initial: _info),
    );
    if (edited == null) return;
    try {
      await services.profiles.updateInfo(_account!.uid, edited);
      if (mounted) setState(() => _info = cleanProfileInfo(edited));
    } catch (e) {
      debugPrint('Saving the profile name failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l.errorGeneric)));
    }
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
    await ServicesScope.of(
      context,
    ).profiles.removeSession(_account!.uid, s.code);
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
              Text(
                sessions.isEmpty
                    ? l.studentDashboardEmpty
                    : l.studentDashboardChooseSession,
              ),
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
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => KnowledgeMapScreen(feedback: feedback),
          ),
        );
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
        Icon(
          Icons.explore_outlined,
          size: 52,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            l.studentDashboardTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l.studentDashboardSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey('dashboard-join'),
          onPressed: _join,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l.homeJoin),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
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
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 300),
                  );
                }
              },
            );
            if (constraints.maxWidth < 500) {
              return Column(children: [map, progress]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: map),
                const SizedBox(width: 8),
                Expanded(child: progress),
              ],
            );
          },
        ),
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
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.studentProfileSignInHint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const ValueKey('profile-sign-in'),
                          onPressed: _signingIn ? null : _signIn,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 52)),
                          icon: _signingIn
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login),
                          label: Text(l.studentProfileSignInGoogle),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l.studentProfileNone,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
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
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              key: const ValueKey('profile-header'),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    ProfileAvatar(info: _info),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _info.displayName ??
                                                l.studentProfileAddName,
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            l.studentProfileSignedInAs(
                                              account.label,
                                            ),
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l.studentProfileEdit,
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: _editInfo,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Join, knowledge map, progress and career path.
                            _dashboard(sessions),
                            const Divider(),
                            const SizedBox(height: 24),
                            Text(
                              l.studentProfileSessionsTitle,
                              key: _progressKey,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l.studentProfileSessionNote,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            if (sessions.isEmpty) Text(l.studentProfileEmpty),
                            // Newest first; the newest one open.
                            for (final (i, s) in sessions.reversed.indexed)
                              Card(
                                key: ValueKey('session-${s.code}'),
                                clipBehavior: Clip.antiAlias,
                                child: ExpansionTile(
                                  initiallyExpanded: i == 0,
                                  title: Text(_sessionName(l, s, lang)),
                                  subtitle: s.addedAt == null
                                      ? null
                                      : Text(
                                          MaterialLocalizations.of(
                                            context,
                                          ).formatMediumDate(
                                            s.addedAt!.toLocal(),
                                          ),
                                        ),
                                  childrenPadding:
                                      const EdgeInsetsDirectional.only(
                                    start: 16,
                                    end: 8,
                                    bottom: 4,
                                  ),
                                  expandedCrossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final c in s.concepts)
                                      if (c.attempts > 0)
                                        ListTile(
                                          key: ValueKey(
                                            'concept-${s.code}-${c.conceptId}',
                                          ),
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(c.name.of(lang)),
                                          subtitle: Text(
                                            '${stateLabel(l, c.state)} · '
                                            '${l.studentFeedbackEvidence(c.correct, c.attempts)}',
                                          ),
                                        ),
                                    Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: IconButton(
                                        tooltip: l.studentProfileRemoveSession,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                        onPressed: () => _remove(s),
                                      ),
                                    ),
                                  ],
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

/// The student's own name and preset picture.
class _EditInfoDialog extends StatefulWidget {
  const _EditInfoDialog({required this.initial});

  final ProfileInfo initial;

  @override
  State<_EditInfoDialog> createState() => _EditInfoDialogState();
}

class _EditInfoDialogState extends State<_EditInfoDialog> {
  late final _name = TextEditingController(text: widget.initial.displayName);
  late int? _avatar = widget.initial.avatar;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _choice(int? value, Widget child, String label) {
    final selected = _avatar == value;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      label: label,
      child: InkWell(
        key: ValueKey('avatar-${value ?? 'none'}'),
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _avatar = value),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: 3,
              color: selected ? scheme.primary : Colors.transparent,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.studentProfileEditTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('profile-name'),
                controller: _name,
                maxLength: ProfileInfo.maxNameLength,
                decoration: InputDecoration(
                  labelText: l.studentProfileNameLabel,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.studentProfilePictureLabel,
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _choice(
                    null,
                    ProfileAvatar(
                      info: ProfileInfo(displayName: _name.text),
                      radius: 22,
                    ),
                    l.studentProfileNoPicture,
                  ),
                  for (var i = 0; i < profileAvatars.length; i++)
                    _choice(
                      i,
                      ProfileAvatar(info: ProfileInfo(avatar: i), radius: 22),
                      '${i + 1}',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.studentProfileInfoPrivate,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.studentProfileCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(ProfileInfo(displayName: _name.text, avatar: _avatar)),
          child: Text(l.studentProfileSaveInfo),
        ),
      ],
    );
  }
}
