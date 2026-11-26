// The phone's own share sheet (WhatsApp, Classroom, mail…) where the
// browser offers one (Web Share API). Elsewhere it returns false and the
// caller copies the text instead.
export 'share_text_stub.dart' if (dart.library.js_interop) 'share_text_web.dart';
