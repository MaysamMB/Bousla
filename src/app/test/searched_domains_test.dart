import 'package:bousla_app/data/firebase/gemini_resource_suggester.dart'
    show searchedDomains;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sites come from chunk titles or domains, not Google redirects', () {
    final d = searchedDomains([
      (
        title: 'youtube.com',
        domain: null,
        uri: 'https://vertexaisearch.cloud.google.com/grounding-api-redirect/x'
      ),
      (title: 'PostgreSQL Documentation', domain: 'postgresql.org', uri: null),
      (title: 'W3Schools', domain: null, uri: 'https://www.w3schools.com/sql/'),
      (title: 'Some page title', domain: null, uri: null),
    ]);
    expect(d, {'youtube.com', 'postgresql.org', 'www.w3schools.com'});
  });
}
