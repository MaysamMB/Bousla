import 'package:flutter/widgets.dart';

import 'data/fake/in_memory_content_repository.dart';
import 'data/ai/question_generator.dart';
import 'data/fake/in_memory_session_repository.dart';
import 'data/repositories/auth_service.dart';
import 'data/repositories/content_repository.dart';
import 'data/repositories/session_repository.dart';

/// Everything screens need from outside the UI. In-memory for
/// development, or Firebase when configured (see main.dart).
class AppServices {
  AppServices({
    required this.content,
    required this.sessions,
    AuthService? auth,
    this.inMemory = false,
    this.questionGenerator,
    Locale initialLocale = const Locale('ar'),
  })  : auth = auth ?? InMemoryAuthService(),
        locale = ValueNotifier(initialLocale);

  factory AppServices.inMemory({Locale initialLocale = const Locale('ar')}) =>
      AppServices(
        content: InMemoryContentRepository(),
        sessions: InMemorySessionRepository(),
        inMemory: true,
        initialLocale: initialLocale,
      );

  final ContentRepository content;
  final SessionRepository sessions;

  /// Instructor sign-in and anonymous student participation.
  final AuthService auth;

  /// True in the offline demo mode (built without Firebase settings): data
  /// lives in this browser tab only and is lost on reload. The app shows a
  /// corner banner so nobody mistakes it for the real deployment.
  final bool inMemory;

  /// AI level 1 (drafting questions from material). Null when not
  /// available, e.g. in the offline demo mode: the screen then hides it.
  final QuestionGenerator? questionGenerator;

  /// Current UI language. Changing it rebuilds the app in that language and
  /// direction (RTL for Arabic, LTR for English).
  final ValueNotifier<Locale> locale;

  /// The course the instructor chose (see `CoursePicker`), shared by the
  /// session and review screens. Null means the first course.
  final ValueNotifier<String?> selectedCourseId = ValueNotifier(null);

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
