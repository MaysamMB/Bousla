import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/join_code.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/bousla_mark.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../answering/answering_screen.dart';
import '../feedback/feedback_screen.dart';

/// Student entry point (owner: student web portal).
///
/// Opened from the home screen, or directly from a link/QR code with
/// [initialCode]. To do: nicer layout for phones, error states polish.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  late final _code = TextEditingController(text: widget.initialCode ?? '');
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final l = AppLocalizations.of(context);
    final services = ServicesScope.of(context);
    final sessions = services.sessions;
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await sessions
          .findByCode(normalizeJoinCode(_code.text))
          .timeout(AnsweringScreen.timeout);
      if (!mounted) return;
      if (session == null) {
        setState(() => _error = l.studentCodeNotFound);
        return;
      }
      if (session.status == SessionStatus.closed) {
        // Closed, but feedback may be published: the same browser keeps the
        // same anonymous participant, so it can still open its feedback.
        final participantId = session.feedbackReleased
            ? await _releasedFeedbackFor(services, session)
            : null;
        if (!mounted) return;
        if (participantId == null) {
          // Released, but nothing for this browser: say where to look
          // instead of only "closed".
          setState(
            () => _error = session.feedbackReleased
                ? l.studentFeedbackNone
                : l.studentSessionClosed,
          );
          return;
        }
        await navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => FeedbackScreen(
              sessionId: session.id,
              participantId: participantId,
            ),
          ),
        );
        return;
      }
      final participantId =
          await sessions.join(session.id).timeout(AnsweringScreen.timeout);
      await navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              AnsweringScreen(session: session, participantId: participantId),
        ),
      );
    } on TimeoutException {
      if (mounted) setState(() => _error = l.studentConnectionSlow);
    } catch (_) {
      if (mounted) setState(() => _error = l.errorGeneric);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The participant ID of this browser if it has released feedback in
  /// [session], else null. Does not join (the session is closed) and does
  /// not create a new identity: [AuthService.ensureParticipant] returns the
  /// existing anonymous user.
  Future<String?> _releasedFeedbackFor(
    AppServices services,
    Session session,
  ) async {
    try {
      final participantId = await services.auth
          .ensureParticipant()
          .timeout(AnsweringScreen.timeout);
      final feedback = await services.sessions
          .watchMyFeedback(session.id, participantId)
          .first
          .timeout(AnsweringScreen.timeout);
      if (feedback == null) {
        // For diagnosis from the browser console: compare with the IDs
        // under sessions/{code}/feedback (first characters only).
        debugPrint(
          'Bousla: no feedback for this browser in ${session.code} '
          '(participant ${participantId.substring(0, 6)}…)',
        );
        return null;
      }
      return participantId;
    } catch (e) {
      // A real failure (connection, permission) is reported as an error,
      // not as "no feedback for you", which would hide it.
      debugPrint('Bousla: feedback lookup failed: $e');
      rethrow;
    }
  }

  // The colours come from the app theme (light, or dark with the switch in
  // the app bar); the dark theme uses this screen's original colours.
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          // The student's optional personal profile (created from their
          // feedback page; the page explains this when there is none yet).
          IconButton(
            key: const ValueKey('open-profile'),
            tooltip: l.studentProfileTitle,
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.of(context).pushNamed('/me'),
          ),
          const LanguageSwitcher(),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // The Bousla mark, large and faint in the empty space above
          // the form (clear of the code field and its messages).
          const BouslaWatermark(alignment: Alignment(0, -0.62)),
          Align(
            // Lower half: the watermark sits in the empty space above.
            alignment: const Alignment(0, 0.5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  l.studentJoinTitle,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Codes are typed left-to-right in both languages.
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: TextField(
                                  controller: _code,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  style: Theme.of(
                                    context,
                                  )
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(letterSpacing: 2),
                                  textAlign: TextAlign.center,
                                  textCapitalization: TextCapitalization.characters,
                                  autofocus: widget.initialCode == null,
                                  decoration: InputDecoration(
                                    labelText: l.studentEnterCode,
                                    errorText: _error,
                                    // Messages such as "open the link on the
                                    // phone you answered from" must be read in
                                    // full, not cut after one line.
                                    errorMaxLines: 4,
                                  ),
                                  onSubmitted: (_) => _busy ? null : _join(),
                                ),
                              ),
                              // Came without a link: remind them the QR code is scanned
                              // with the phone's own camera (it opens this page with the
                              // code filled in). Outside the LTR box, so Arabic reads RTL.
                              if (widget.initialCode == null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  l.studentScanHint,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy ? null : _join,
                        style:
                            FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                        child: _busy
                            ? SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  semanticsLabel: l.studentJoin,
                                ),
                              )
                            : Text(l.studentJoin),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
