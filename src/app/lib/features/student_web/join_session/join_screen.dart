import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/join_code.dart';
import '../../../data/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';
import '../answering/answering_screen.dart';

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
    final sessions = ServicesScope.of(context).sessions;
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
        setState(() => _error = l.studentSessionClosed);
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.studentJoinTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Codes are typed left-to-right in both languages.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: _code,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    autofocus: widget.initialCode == null,
                    decoration: InputDecoration(
                      labelText: l.studentEnterCode,
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _busy ? null : _join(),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  child: Text(l.studentJoin),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
