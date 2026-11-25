// Remembers the light/dark choice in this browser (localStorage), so it
// stays after a reload. Elsewhere (tests, other platforms) nothing is kept.
export 'theme_mode_store_stub.dart'
    if (dart.library.js_interop) 'theme_mode_store_web.dart';
