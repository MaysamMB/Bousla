// Saves a PNG on the student's device. On the web: the phone's share sheet
// when it can share files (on iPhone: "Save Image" puts it in Photos),
// otherwise a normal download. Other platforms are not used by students.
export 'save_image_stub.dart' if (dart.library.js_interop) 'save_image_web.dart';
