import 'package:bousla_app/app.dart';
import 'package:bousla_app/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the app bar switch toggles light and dark everywhere',
      (tester) async {
    final services = AppServices.inMemory(initialLocale: const Locale('en'));
    await tester.pumpWidget(BouslaApp(services: services));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/join/ABC234');
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.light);
    expect(Theme.of(tester.element(find.text('Join').last)).brightness,
        Brightness.light);

    await tester.tap(find.byTooltip('Dark mode'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.dark);
    expect(services.themeMode.value, ThemeMode.dark);
    expect(Theme.of(tester.element(find.text('Join').last)).brightness,
        Brightness.dark);
    // The same button now offers light mode.
    expect(find.byTooltip('Light mode'), findsOneWidget);

    await tester.tap(find.byTooltip('Light mode'));
    await tester.pumpAndSettle();
    expect(app().themeMode, ThemeMode.light);
  });
}
