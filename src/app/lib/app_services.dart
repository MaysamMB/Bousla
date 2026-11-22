import 'package:flutter/widgets.dart';

import 'data/fake/in_memory_content_repository.dart';
import 'data/fake/in_memory_session_repository.dart';
import 'data/repositories/content_repository.dart';
import 'data/repositories/session_repository.dart';

/// Everything screens need from outside the UI. Swap the in-memory
/// repositories for Firestore ones in one place (main.dart).
class AppServices {
  AppServices({
    required this.content,
    required this.sessions,
    Locale initialLocale = const Locale('ar'),
  }) : locale = ValueNotifier(initialLocale);

  factory AppServices.inMemory({Locale initialLocale = const Locale('ar')}) =>
      AppServices(
        content: InMemoryContentRepository(),
        sessions: InMemorySessionRepository(),
        initialLocale: initialLocale,
      );

  final ContentRepository content;
  final SessionRepository sessions;

  /// Current UI language. Changing it rebuilds the app in that language and
  /// direction (RTL for Arabic, LTR for English).
  final ValueNotifier<Locale> locale;

  void toggleLanguage() => locale.value = locale.value.languageCode == 'ar'
      ? const Locale('en')
      : const Locale('ar');
}

/// Gives widgets access to [AppServices] with `ServicesScope.of(context)`.
class ServicesScope extends InheritedWidget {
  const ServicesScope({
    super.key,
    required this.services,
    required super.child,
  });

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ServicesScope>();
    assert(scope != null, 'No ServicesScope above this widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(ServicesScope oldWidget) =>
      services != oldWidget.services;
}
