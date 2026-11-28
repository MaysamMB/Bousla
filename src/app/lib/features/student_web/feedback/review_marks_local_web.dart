import 'package:web/web.dart' as web;

// Storage can be blocked (private mode, settings): then reads give nothing
// and writes are dropped, never an error on the page.
String? readLocal(String key) {
  try {
    return web.window.localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

void writeLocal(String key, String value) {
  try {
    web.window.localStorage.setItem(key, value);
  } catch (_) {
    // Not kept.
  }
}
