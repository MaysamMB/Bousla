import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/feedback.dart';
import '../../../data/repositories/auth_service.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../l10n/app_localizations.dart';
import 'consent_dialog.dart';
import 'profile_screen.dart';

/// At the end of the feedback page: keep this session in the student's own
/// profile (optional, architecture §10). Consent first, then a Google
/// sign-in that keeps the same UID, then the session is copied from this
/// released feedback. The instructor sees nothing new.
class SaveProgressCard extends StatefulWidget {
  const SaveProgressCard({
    super.key,
    required this.sessionId,
    required this.feedback,
  });

  final String sessionId;
  final StudentFeedback feedback;

  @override
  State<SaveProgressCard> createState() => _SaveProgressCardState();
}

class _SaveProgressCardState extends State<SaveProgressCard> {
  var _saved = false;
  var _busy = false;
  var _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checked) {
      _checked = true;
      _check();
    }
  }

  /// Already in the profile? (Only when an account is linked.)
  Future<void> _check() async {
    final services = ServicesScope.of(context);
    final account = services.auth.studentAccount;
    if (account == null) return;
    try {
      final saved = await services.profiles.hasSession(account.uid, widget.sessionId);
      if (mounted && saved) setState(() => _saved = true);
    } catch (_) {
      // Shown as not saved; saving again is harmless.
    }
  }

  String _problemText(AppLocalizations l, StudentLinkProblem p) => switch (p) {
        StudentLinkProblem.cancelled => l.studentProfileErrCancelled,
        StudentLinkProblem.accountInUse => l.studentProfileErrInUse,
        StudentLinkProblem.notEnabled => l.studentProfileErrNotEnabled,
        StudentLinkProblem.network => l.studentProfileErrNetwork,
        _ => l.studentProfileErrFailed,
      };

  Future<void> _save() async {
    final services = ServicesScope.of(context);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var account = services.auth.studentAccount;
      final consented = account == null
          ? null
          : await services.profiles.consentVersion(account.uid);
      final needsConsent =
          consented == null || consented < profileConsentVersion;
      // Consent before anything is linked or stored, and again when the
      // text changed. No spinner while the student reads it.
      if (needsConsent) {
        if (!mounted) return;
        final agreed = await showProfileConsent(context);
        if (agreed != true) return;
      }
      if (mounted) setState(() => _busy = true);
      account ??= await services.auth.linkStudentAccount();
      if (needsConsent) await services.profiles.create(account.uid);
      final session =
          await services.sessions.watchSession(widget.sessionId).first;
      await services.profiles.saveSession(account.uid, session, widget.feedback);
      if (mounted) setState(() => _saved = true);
    } on StudentLinkFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_problemText(l, e.problem))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l.studentProfileErrFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('save-progress'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _saved ? Icons.bookmark_added : Icons.bookmark_add_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _saved ? l.studentProfileSaved : l.studentProfileSaveTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (!_saved) ...[
              const SizedBox(height: 6),
              Text(l.studentProfileSaveHint, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _saved
                  ? OutlinedButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.person_outline),
                      label: Text(l.studentProfileOpen),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bookmark_add_outlined),
                      label: Text(l.studentProfileSaveAction),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
