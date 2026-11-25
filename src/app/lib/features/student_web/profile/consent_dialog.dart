import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// The consent text for the optional profile (version
/// `profileConsentVersion`). Two equal choices; nothing is linked or stored
/// unless the student agrees. True when they agreed.
Future<bool?> showProfileConsent(BuildContext context) => showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        final theme = Theme.of(context);
        Widget point(IconData icon, String text) => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text(text)),
                ],
              ),
            );
        return AlertDialog(
          key: const ValueKey('profile-consent'),
          title: Text(l.studentProfileConsentTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.studentProfileConsentIntro),
                point(Icons.lock_outline, l.studentProfileConsentWho),
                point(Icons.block, l.studentProfileConsentNotKept),
                point(Icons.info_outline, l.studentProfileConsentEstimates),
                point(Icons.delete_outline, l.studentProfileConsentDelete),
                point(Icons.login, l.studentProfileConsentSignIn),
              ],
            ),
          ),
          actions: [
            // Equal weight: declining is as easy as agreeing.
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l.studentProfileConsentDecline),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l.studentProfileConsentAgree),
            ),
          ],
        );
      },
    );
