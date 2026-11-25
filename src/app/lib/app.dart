import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_services.dart';
import 'features/home/home_screen.dart';
import 'features/instructor/auth/instructor_gate.dart';
import 'features/instructor/content_review/content_review_screen.dart';
import 'features/instructor/resources/resources_screen.dart';
import 'features/instructor/sessions/create_session_screen.dart';
import 'features/student_web/join_session/join_screen.dart';
import 'l10n/app_localizations.dart';

/// Routes:
///   /                 home (choose role)
///   /instructor       instructor: create and run a session
///   /instructor/review  instructor: review, edit, reject and add questions
///   /instructor/resources  instructor: learning resources (add, AI suggestions)
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
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: services.themeMode,
        builder: (context, themeMode, _) => ValueListenableBuilder<Locale>(
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
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          onGenerateRoute: _route,
          builder: services.inMemory
              ? (context, child) => Banner(
                    message: AppLocalizations.of(context).appInMemoryBanner,
                    location: BannerLocation.bottomStart,
                    layoutDirection: Directionality.of(context),
                    textDirection: Directionality.of(context),
                    color: const Color(0xFFB3261E),
                    // The ribbon does not inherit the theme: use the bundled
                    // fonts so Arabic does not show as empty boxes.
                    textStyle: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      fontFamily: 'Sora',
                      fontFamilyFallback: ['IBMPlexSansArabic'],
                    ),
                    child: child!,
                  )
              : null,
        ),
      ),
      ),
    );
  }

  // The Bousla identity (find-your-bousla.base44.app/assets). Fonts, per
  // character: Latin and digits from Sora, Arabic from IBM Plex Sans Arabic,
  // arrows/math from NotoSansMath (see pubspec.yaml).
  static const _font = 'Sora';
  static const _fallback = ['IBMPlexSansArabic', 'NotoSansMath'];

  static const midnight = Color(0xFF0B1230);
  static const indigo = Color(0xFF12214F);
  static const signalTeal = Color(0xFF34E3B6);
  static const darkTeal = Color(0xFF0E9E86);
  static const directionGold = Color(0xFFFFB020);
  static const cloud = Color(0xFFF6F8FC);
  static const border = Color(0xFFE3E8F2);
  static const textGrey = Color(0xFF5B6480);

  /// Light: cloud pages, dark-teal actions (readable on light), midnight text.
  static final lightTheme = () {
    final colors = ColorScheme.fromSeed(seedColor: signalTeal).copyWith(
      primary: darkTeal,
      onPrimary: Colors.white,
      tertiary: directionGold,
      onTertiary: midnight,
      surface: Colors.white,
      onSurface: midnight,
      onSurfaceVariant: textGrey,
      outlineVariant: border,
    );
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: cloud,
      appBarTheme: const AppBarTheme(backgroundColor: cloud),
      dividerColor: border,
      fontFamily: _font,
      fontFamilyFallback: _fallback,
    );
  }();

  /// Dark: midnight pages, indigo surfaces, signal-teal actions.
  static final darkTheme = () {
    final colors = ColorScheme.fromSeed(
      seedColor: signalTeal,
      brightness: Brightness.dark,
    ).copyWith(
      primary: signalTeal,
      onPrimary: midnight,
      tertiary: directionGold,
      onTertiary: midnight,
      surface: midnight,
      onSurface: Colors.white,
      surfaceContainerLowest: midnight,
      surfaceContainerLow: indigo,
      surfaceContainer: indigo,
      surfaceContainerHigh: const Color(0xFF1A2C63),
      surfaceContainerHighest: const Color(0xFF223672),
      outlineVariant: const Color(0xFF26386E),
    );
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: midnight,
      appBarTheme: const AppBarTheme(backgroundColor: midnight),
      fontFamily: _font,
      fontFamilyFallback: _fallback,
    );
  }();

  static Route<void> _route(RouteSettings settings) {
    final segments = Uri.parse(settings.name ?? '/').pathSegments;
    final Widget page = switch (segments) {
      ['instructor', 'review'] => const InstructorGate(
          child: ContentReviewScreen(),
        ),
      ['instructor', 'resources'] => const InstructorGate(
          child: ResourcesScreen(),
        ),
      ['instructor', ...] => const InstructorGate(child: CreateSessionScreen()),
      ['join'] => const JoinScreen(),
      ['join', final code, ...] => JoinScreen(initialCode: code),
      _ => const HomeScreen(),
    };
    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }
}
