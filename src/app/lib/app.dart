import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_services.dart';
import 'features/home/home_screen.dart';
import 'features/instructor/content_review/content_review_screen.dart';
import 'features/instructor/sessions/create_session_screen.dart';
import 'features/student_web/join_session/join_screen.dart';
import 'l10n/app_localizations.dart';

/// Routes:
///   /                 home (choose role)
///   /instructor       instructor: create and run a session
///   /instructor/review  instructor: review, edit, reject and add questions
///   /join             student: type a join code
///   /join/<CODE>      student: join directly (link or QR code)
///
/// On the web the default URL strategy uses a hash, so a join link looks like
/// https://<host>/#/join/ABC123.
class BouslaApp extends StatelessWidget {
  const BouslaApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: services,
      child: ValueListenableBuilder<Locale>(
        valueListenable: services.locale,
        builder: (context, locale, _) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF1B6E6A),
            useMaterial3: true,
            // Per-character fallback: Latin from NotoSans, Arabic from
            // NotoSansArabic, arrows/math from NotoSansMath (see pubspec.yaml).
            fontFamily: 'NotoSans',
            fontFamilyFallback: const ['NotoSansArabic', 'NotoSansMath'],
          ),
          onGenerateRoute: _route,
        ),
      ),
    );
  }

  static Route<void> _route(RouteSettings settings) {
    final segments = Uri.parse(settings.name ?? '/').pathSegments;
    final Widget page = switch (segments) {
      ['instructor', 'review'] => const ContentReviewScreen(),
      ['instructor', ...] => const CreateSessionScreen(),
      ['join'] => const JoinScreen(),
      ['join', final code, ...] => JoinScreen(initialCode: code),
      _ => const HomeScreen(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }
}
