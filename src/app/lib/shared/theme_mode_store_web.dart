import 'package:web/web.dart' as web;

const _key = 'bousla.themeMode';

/// The stored choice: 'light', 'dark' or null. Storage can be blocked
/// (private mode, settings): then there is simply no stored choice.
String? loadThemeModeName() {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void saveThemeModeName(String name) {
  try {
    web.window.localStorage.setItem(_key, name);
  } catch (_) {
    // Not remembered; the choice still applies until the page is closed.
  }
}
