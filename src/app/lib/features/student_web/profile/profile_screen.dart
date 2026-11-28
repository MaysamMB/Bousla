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
import '../../../shared/widgets/bousla_mark.dart';
import 'profile_avatar.dart';

/// "My profile": the student's own saved sessions (architecture §10).
/// A header with the student's own name and preset picture, then each saved
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_account == null) {
      _account = ServicesScope.of(context).auth.studentAccount;
      _loadInfo();
    }
    _sessions ??= _load();
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
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
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
                                              account.label),
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
                          // Career path preview, from these sessions only.
                          Card(
                            key: const ValueKey('open-career'),
                            child: ListTile(
                              leading: const Icon(Icons.work_outline),
                              title: Text(l.studentCareerOpen),
                              subtitle: Text(l.studentCareerOpenHint),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      CareerScreen(sessions: sessions),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            l.studentProfileSessionsTitle,
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
                                    : Text(MaterialLocalizations.of(context)
                                        .formatMediumDate(
                                            s.addedAt!.toLocal())),
                                childrenPadding:
                                    const EdgeInsetsDirectional.only(
                                        start: 16, end: 8, bottom: 4),
                                expandedCrossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  for (final c in s.concepts)
                                    if (c.attempts > 0)
                                      ListTile(
                                        key: ValueKey(
                                            'concept-${s.code}-${c.conceptId}'),
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
                                          Icons.remove_circle_outline),
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
                decoration:
                    InputDecoration(labelText: l.studentProfileNameLabel),
              ),
              const SizedBox(height: 8),
              Text(l.studentProfilePictureLabel,
                  style: theme.textTheme.labelLarge),
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
              Text(l.studentProfileInfoPrivate,
                  style: theme.textTheme.bodySmall),
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
          onPressed: () => Navigator.of(context).pop(
            ProfileInfo(displayName: _name.text, avatar: _avatar),
          ),
          child: Text(l.studentProfileSaveInfo),
        ),
      ],
    );
  }
}
