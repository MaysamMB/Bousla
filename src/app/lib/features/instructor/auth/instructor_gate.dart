import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/repositories/auth_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';

/// Shows [child] only to a signed-in, approved instructor; otherwise an
/// email and password form, or a "waiting for approval" screen for an
/// account not yet in the approved list. In development (in-memory
/// services) there is always an instructor, so [child] is shown directly.
///
/// This screen only explains; the security rules are what refuse an
/// unapproved account (firebase/firestore.rules, `isInstructor`).
///
/// Students are never asked to sign in: they join anonymously.
class InstructorGate extends StatelessWidget {
  const InstructorGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = ServicesScope.of(context).auth;
    if (!auth.requiresSignIn) return child;
    return StreamBuilder<String?>(
      stream: auth.instructorChanges(),
      initialData: auth.instructorId,
      builder: (context, snapshot) => switch (snapshot.data) {
        null => const _SignInForm(),
        // A new check for each account.
        final uid => _ApprovalCheck(key: ValueKey(uid), uid: uid, child: child),
      },
    );
  }
}

class _ApprovalCheck extends StatefulWidget {
  const _ApprovalCheck({super.key, required this.uid, required this.child});

  final String uid;
  final Widget child;

  @override
  State<_ApprovalCheck> createState() => _ApprovalCheckState();
}

class _ApprovalCheckState extends State<_ApprovalCheck> {
  Future<bool>? _approved;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _approved ??= ServicesScope.of(context).auth.isApprovedInstructor();
  }

  void _checkAgain() => setState(() {
    _approved = ServicesScope.of(context).auth.isApprovedInstructor();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _approved,
      builder: (context, snapshot) {
        if (snapshot.data == true) return widget.child;
        final l = AppLocalizations.of(context);
        final auth = ServicesScope.of(context).auth;
        final waiting = snapshot.connectionState != ConnectionState.done;
        return Scaffold(
          appBar: AppBar(
            title: Text(l.authTitle),
            actions: const [LanguageSwitcher()],
          ),
          body: Center(
            child: waiting
                ? const CircularProgressIndicator()
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (snapshot.hasError)
                          Text(l.authErrorNetwork)
                        else ...[
                          Text(
                            l.authNotApprovedTitle,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(l.authNotApprovedBody),
                          const SizedBox(height: 12),
                          // The ID the admin adds in the Firebase console.
                          SelectableText(
                            widget.uid,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _checkAgain,
                          child: Text(l.authCheckAgain),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: auth.signOut,
                          child: Text(l.authSignOut),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _SignInForm extends StatefulWidget {
  const _SignInForm();

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  AuthProblem? _problem;

  /// Shown after the generic message when the problem is unknown.
  String? _detail;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool register}) async {
    final auth = ServicesScope.of(context).auth;
    setState(() {
      _busy = true;
      _problem = null;
      _detail = null;
    });
    try {
      if (register) {
        await auth.registerInstructor(_email.text, _password.text);
      } else {
        await auth.signInInstructor(_email.text, _password.text);
      }
    } on AuthFailure catch (e) {
      if (mounted) {
        setState(() {
          _problem = e.problem;
          _detail = e.code;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _problem = AuthProblem.unknown;
          _detail = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _message(AppLocalizations l, AuthProblem problem) =>
      switch (problem) {
        AuthProblem.wrongCredentials => l.authErrorWrongCredentials,
        AuthProblem.emailInUse => l.authErrorEmailInUse,
        AuthProblem.weakPassword => l.authErrorWeakPassword,
        AuthProblem.invalidEmail => l.authErrorInvalidEmail,
        AuthProblem.network => l.authErrorNetwork,
        AuthProblem.tooManyAttempts => l.authErrorTooManyAttempts,
        AuthProblem.notEnabled => l.authErrorNotEnabled,
        AuthProblem.unknown => l.authFailed,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.authTitle),
        actions: const [LanguageSwitcher()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l.authEmail),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l.authPassword),
                onSubmitted: (_) => _submit(register: false),
              ),
              if (_problem case final problem?) ...[
                const SizedBox(height: 12),
                Text(
                  problem == AuthProblem.unknown && _detail != null
                      ? '${_message(l, problem)}\n($_detail)'
                      : _message(l, problem),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : () => _submit(register: false),
                child: Text(l.authSignIn),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _submit(register: true),
                child: Text(l.authRegister),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
