import 'package:bousla_app/shared/text_direction.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SQL and English read left-to-right, Arabic right-to-left', () {
    expect(textDirectionOf('SELECT name FROM Student WHERE gpa > 3;'),
        TextDirection.ltr);
    expect(textDirectionOf('Can a primary key be NULL?'), TextDirection.ltr);
    expect(textDirectionOf('المفتاح الأساسي (Primary Key)'), TextDirection.rtl);
    expect(textDirectionOf('أي استعلام يعرض الأسماء؟'), TextDirection.rtl);
  });
}
