import 'package:web/web.dart' as web;

const _key = 'bousla.lastJoinCode';

/// A code older than this is not offered again (another day, another
/// session).
const _keepFor = Duration(hours: 6);

/// The last joined code, if still recent. Stored as "CODE|millisecondsSinceEpoch".
/// Storage can be blocked (private mode, settings): then nothing is offered.
String? loadLastJoinCode() {
  try {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    final at = int.tryParse(parts[1]);
    if (at == null) return null;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    return age > _keepFor ? null : parts[0];
  } catch (_) {
    return null;
  }
}

void saveLastJoinCode(String code) {
  try {
    web.window.localStorage
        .setItem(_key, '$code|${DateTime.now().millisecondsSinceEpoch}');
  } catch (_) {
    // Not remembered; the student types the code again after a reload.
  }
}
