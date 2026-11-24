import 'dart:typed_data';

/// Not available outside the browser (students only use the web portal).
Future<void> saveImage(Uint8List png, String fileName) async =>
    throw UnsupportedError('Saving an image is only available on the web');
