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

  /// The student agreed but the browser blocked the sign-in window: the
  /// next tap opens it straight away (no dialog in between).
  var _agreedAwaitingSignIn = false;
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
      final saved =
          await services.profiles.hasSession(account.uid, widget.sessionId);
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
        StudentLinkProblem.instructorSignedIn => l.studentProfileErrInstructor,
        _ => l.studentProfileErrFailed,
      };

  /// This browser's handover, once the Google account turned out to have a
  /// profile from another browser (see [_linkOrSwitch]).
  String? _handoverId;

  /// The student chose to sign in to that profile but the window did not
  /// open (blocked or closed): the next tap opens it straight away.
  var _awaitingSwitch = false;

  /// Links this browser to Google; if that Google account already has a
  /// profile (another browser), offers to sign in to it and hand this
  /// session over. Null when the student declined.
  Future<StudentAccount?> _linkOrSwitch(AppServices services) async {
    try {
      return await services.auth.linkStudentAccount();
    } on StudentLinkFailure catch (e) {
      if (e.problem != StudentLinkProblem.accountInUse) rethrow;
    }
    // Still anonymous here: only this browser can hand its feedback over.
    final me = await services.auth.ensureParticipant();
    _handoverId = await services.profiles.createHandover(widget.sessionId, me);
    if (!mounted) return null;
    setState(() => _busy = false);
    final go = await showExistingProfileDialog(context);
    if (go != true) {
      _handoverId = null;
      return null;
    }
    if (mounted) setState(() => _busy = true);
    _awaitingSwitch = true;
    final account = await services.auth.switchToLinkedStudentAccount();
    _awaitingSwitch = false;
    return account;
  }

  Future<void> _save() async {
    final services = ServicesScope.of(context);
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Read now: after a switch to another account this browser's
      // anonymous identity is gone.
      final session = services.sessions.watchSession(widget.sessionId).first
        ..ignore(); // Awaited below; not needed when the student stops.
      var account = services.auth.studentAccount;
      // The student already agreed in an earlier tap.
      var agreed = _agreedAwaitingSignIn || _awaitingSwitch;
      // A Google window straight from this tap (Safari blocks it otherwise).
      if (_awaitingSwitch) {
        account = await services.auth.switchToLinkedStudentAccount();
        _awaitingSwitch = false;
      } else if (_agreedAwaitingSignIn && account == null) {
        account = await _linkOrSwitch(services);
        if (account == null) return;
      }
      if (!agreed) {
        final consented = account == null
            ? null
            : await services.profiles.consentVersion(account.uid);
        // Consent before anything is linked or stored, and again when the
        // text changed. No spinner while the student reads it.
        if (consented == null || consented < profileConsentVersion) {
          if (!mounted) return;
          if (await showProfileConsent(context) != true) return;
          agreed = true;
        }
      }
      if (mounted) setState(() => _busy = true);
      account ??= await _linkOrSwitch(services);
      if (account == null) return;
      if (agreed) {
        final consented = await services.profiles.consentVersion(account.uid);
        if (consented == null || consented < profileConsentVersion) {
          await services.profiles.create(account.uid);
        }
      }
      await services.profiles.saveSession(
        account.uid,
        await session,
        widget.feedback,
        handoverId: _handoverId,
      );
      if (mounted) {
        setState(() {
          _saved = true;
          _agreedAwaitingSignIn = false;
          _handoverId = null;
        });
      }
    } on StudentLinkFailure catch (e) {
      final retry = e.problem == StudentLinkProblem.popupBlocked ||
          e.problem == StudentLinkProblem.cancelled;
      if (_awaitingSwitch && retry) {
        // The handover is written; the next tap opens the window again.
        if (mounted) setState(() {});
        return;
      }
      if (e.problem == StudentLinkProblem.popupBlocked) {
        if (mounted) setState(() => _agreedAwaitingSignIn = true);
        return;
      }
      _reset();
      debugPrint('Linking the profile failed: $e');
      final text = _problemText(l, e.problem);
      // A general message carries a code, so the failure can be diagnosed.
      messenger.showSnackBar(SnackBar(
        content: Text(text == l.studentProfileErrFailed
            ? '$text (${e.detail ?? e.problem.name})'
            : text),
      ));
    } catch (e) {
      // E.g. the handover is older than 10 minutes: start again.
      _reset();
      debugPrint('Saving to the profile failed: $e');
      messenger.showSnackBar(SnackBar(
        content: Text('${l.studentProfileErrFailed} (${_errorCode(e)})'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    _handoverId = null;
    _awaitingSwitch = false;
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
                      label: Text(
                        _agreedAwaitingSignIn || _awaitingSwitch
                            ? l.studentProfileContinueSignIn
                            : l.studentProfileSaveAction,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short code for an unexpected error (Firebase errors have one, e.g.
/// "permission-denied"), shown so a failure can be diagnosed.
String _errorCode(Object e) {
  try {
    final code = (e as dynamic).code;
    if (code is String && code.isNotEmpty) return code;
  } catch (_) {}
  return e.runtimeType.toString();
}
