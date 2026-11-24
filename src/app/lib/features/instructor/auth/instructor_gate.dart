import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/language_switcher.dart';

/// Shows [child] only to a signed-in instructor; otherwise an email and
/// password form. In development (in-memory services) there is always an
/// instructor, so [child] is shown directly.
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
      builder: (context, snapshot) =>
          snapshot.data == null ? const _SignInForm() : child,
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
  var _failed = false;

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
      _failed = false;
    });
    try {
      if (register) {
        await auth.registerInstructor(_email.text, _password.text);
      } else {
        await auth.signInInstructor(_email.text, _password.text);
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
              if (_failed) ...[
                const SizedBox(height: 12),
                Text(
                  l.authFailed,
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
