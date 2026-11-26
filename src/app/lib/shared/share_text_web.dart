import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// False when the browser has no share sheet (most desktop browsers) or the
/// person closed it.
Future<bool> shareText({required String text, String? title}) async {
  try {
    await web.window.navigator
        .share(web.ShareData(text: text, title: title ?? ''))
        .toDart;
    return true;
  } catch (_) {
    return false;
  }
}
