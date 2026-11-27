// Remembers the last session code this browser joined (localStorage), so a
// reload brings the student back to the join screen with the code filled
// in. Elsewhere (tests, other platforms) nothing is kept.
export 'last_join_code_store_stub.dart'
    if (dart.library.js_interop) 'last_join_code_store_web.dart';
