import 'dart:math';

/// Letters and digits that are hard to confuse when read aloud or typed
/// (no 0/O, 1/I/L).
const joinCodeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const joinCodeLength = 6;

/// Random join code from a cryptographically secure source.
String generateJoinCode([Random? random]) {
  final rng = random ?? Random.secure();
  return List.generate(
    joinCodeLength,
    (_) => joinCodeAlphabet[rng.nextInt(joinCodeAlphabet.length)],
  ).join();
}

/// Uppercases and removes spaces and dashes, so "abc-d23" matches "ABCD23".
String normalizeJoinCode(String input) =>
    input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
