import 'package:web/web.dart' as web;

/// Opens [url] in a new tab, without giving that page access to this one.
Future<void> openLink(Uri url) async {
  web.window.open(url.toString(), '_blank', 'noopener,noreferrer');
}
