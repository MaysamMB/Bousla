import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Shares [png] as a file where the browser allows it (phones), otherwise
/// downloads it. The image never leaves the device unless the student
/// chooses where to send it in the share sheet.
Future<void> saveImage(Uint8List png, String fileName) async {
  final parts = [png.toJS].toJS;
  final file = web.File(parts, fileName, web.FilePropertyBag(type: 'image/png'));
  final data = web.ShareData(files: [file].toJS);
  final navigator = web.window.navigator;
  try {
    if (navigator.canShare(data)) {
      await navigator.share(data).toDart;
      return;
    }
  } catch (e) {
    // The student closed the share sheet: nothing else to do.
    if (e.toString().contains('AbortError')) return;
    // Sharing refused (e.g. not allowed here): fall back to a download.
  }
  final url = web.URL.createObjectURL(
    web.Blob(parts, web.BlobPropertyBag(type: 'image/png')),
  );
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(link);
  link.click();
  link.remove();
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
}
