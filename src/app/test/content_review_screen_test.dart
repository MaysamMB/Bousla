import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:bousla_app/data/models.dart';
import 'package:bousla_engine/bousla_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Only taps, no typing: a focused text field's blinking cursor keeps
// pumpAndSettle busy (see widget_smoke_test.dart).
void main() {
  Future<AppServices> openReview(WidgetTester tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I'm an instructor"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review questions'));
    await tester.pumpAndSettle();
    return services;
  }

  Future<void> tapFirst(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('instructor approves one AI draft and rejects the other', (
    tester,
  ) async {
    final services = await openReview(tester);

    expect(find.text('Waiting (2)'), findsOneWidget);
    expect(find.text('Approved (4)'), findsOneWidget);
    expect(find.text('AI draft'), findsWidgets);

    await tapFirst(tester, 'Approve');
    expect(find.text('Waiting (1)'), findsOneWidget);
    expect(find.text('Approved (5)'), findsOneWidget);

    await tapFirst(tester, 'Reject');
    expect(find.text('Reject questions (1)'), findsOneWidget);
    await tester.tap(find.text('Unclear wording'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Rejected (1)'), findsOneWidget);
    expect(find.textContaining('rejected 1'), findsOneWidget);

    final all = await tester.runAsync(
      () => services.content.listQuestions(
        'database_systems',
        approvedOnly: false,
      ),
    );
    final rejected = all!.singleWhere((q) => q.id == 'db_rm_002');
    expect(rejected.status, ReviewStatus.rejected);
    expect(rejected.rejectionReason, RejectionReason.unclear);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('instructor selects drafts and rejects them together', (
    tester,
  ) async {
    await openReview(tester);

    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(2));
    await tester.tap(boxes.at(0));
    await tester.pumpAndSettle();
    await tester.ensureVisible(boxes.at(1));
    await tester.pumpAndSettle();
    await tester.tap(boxes.at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reject selected (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject without a reason'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Rejected (2)'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
