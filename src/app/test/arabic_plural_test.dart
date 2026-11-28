import 'package:bousla_app/l10n/app_localizations_ar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Arabic respondent counts use the right plural form', () {
    final l = AppLocalizationsAr();
    expect(l.instructorInsightsEvidence(1, 100), startsWith('أجاب طالب واحد'));
    expect(l.instructorInsightsEvidence(2, 50), startsWith('أجاب طالبان'));
    expect(l.instructorInsightsEvidence(5, 60), startsWith('أجاب 5 طلاب'));
    expect(l.instructorInsightsEvidence(12, 60), startsWith('أجاب 12 طالبًا'));
    expect(l.instructorInsightsEvidence(5, 60), endsWith('60%'));
  });
}
