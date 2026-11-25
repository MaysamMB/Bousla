import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/fake/in_memory_content_repository.dart';
import 'package:bousla_app/data/fake/in_memory_session_repository.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_app/features/instructor/course_picker.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _networks = Course(
  id: 'networks',
  name: LocalizedText(ar: 'الشبكات', en: 'Computer Networks'),
);

/// The sample course plus an empty second course.
class _TwoCourses extends InMemoryContentRepository {
  @override
  Future<List<Course>> listCourses() async => [
        ...await super.listCourses(),
        _networks,
      ];
}

void main() {
  group('chooseCourse', () {
    const db = Course(
      id: 'database_systems',
      name: LocalizedText(ar: 'قواعد', en: 'DB'),
    );

    test('uses the chosen course, otherwise the first', () {
      expect(chooseCourse([db, _networks], 'networks'), _networks);
      expect(chooseCourse([db, _networks], null), db);
      // A choice from another account or a removed course.
      expect(chooseCourse([db, _networks], 'gone'), db);
      expect(chooseCourse(const [], 'networks'), isNull);
    });
  });

  Future<AppServices> openInstructor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final services = AppServices(
      content: _TwoCourses(),
      sessions: InMemorySessionRepository(),
      inMemory: true,
      initialLocale: const Locale('en'),
    );
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    return services;
  }

  Future<void> choose(WidgetTester tester, String course) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(course).last);
    await tester.pumpAndSettle();
  }

  testWidgets('instructor switches course; review screen follows', (
    tester,
  ) async {
    final services = await openInstructor(tester);

    expect(find.text('Database Systems'), findsOneWidget);
    expect(find.text('4 approved questions will be used'), findsOneWidget);

    await choose(tester, 'Computer Networks');
    expect(services.selectedCourseId.value, 'networks');
    expect(find.text('0 approved questions will be used'), findsOneWidget);
    final create = find.widgetWithText(FilledButton, 'Create session');
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.tap(find.text('Review questions'));
    await tester.pumpAndSettle();
    expect(find.text('Computer Networks'), findsOneWidget);
    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Approved (0)'), findsOneWidget);

    await choose(tester, 'Database Systems');
    expect(services.selectedCourseId.value, 'database_systems');
    expect(find.text('Waiting (2)'), findsOneWidget);
  });

  testWidgets('course cannot change while a session runs', (tester) async {
    await openInstructor(tester);
    await tester.tap(find.text('Create session'));
    // The dialog asks whether to review questions first.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create session now'));
    await tester.pumpAndSettle();
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(field.onChanged, isNull);
  });

  testWidgets('approved count refreshes after the review screen', (
    tester,
  ) async {
    await openInstructor(tester);
    expect(find.text('4 approved questions will be used'), findsOneWidget);
    await tester.tap(find.text('Review questions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('5 approved questions will be used'), findsOneWidget);
  });
}
