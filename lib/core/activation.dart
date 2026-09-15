/// Activation keys for the gated extras.
///
/// A key is `KIU-<body>-<checksum>`: a four-character body the developer picks
/// (or generates at random) and a four-character checksum derived from that
/// body plus [_salt]. Nothing is stored server-side and no list of issued keys
/// ships in the app — [isValidActivationKey] recomputes the checksum and
/// compares, so any correctly-formed body is a distinct valid key. That is what
/// lets a leaked key be traced back to the person it was handed to.
///
/// **This is a soft gate, not a security boundary.** [_salt] ships inside the
/// APK, so anyone who decompiles the app can mint keys; R8 raises that bar but
/// does not move it. The point is to keep the feature off by default and route
/// users to the developer, not to withstand an attacker. Nothing secret sits
/// behind the check: the gated action runs against the user's own LMS session.
///
/// `tool/generate_activation_key.py` reimplements [_checksum] exactly. The two
/// must stay in lockstep — [activationTestVector] is pinned in both so a change
/// to one without the other fails the test suite rather than silently
/// invalidating every key already handed out.
library;

/// Mixed into the checksum so a body alone does not determine it.
const String _salt = 'kiu-activation-2026-v1';

/// Characters a key may use, in checksum-index order.
///
/// Deliberately missing `O`, `0`, `I` and `1`: keys get read off one screen and
/// retyped into another, and those pairs are the ones that get misread.
const String activationAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Fixed prefix, so a key is recognizable as one when pasted into a chat.
const String _prefix = 'KIU';

/// Length of both the body and the checksum block.
const int _blockLength = 4;

/// A known-good key, asserted by both the Dart tests and the Python generator.
///
/// Any edit to [_salt], [activationAlphabet] or [_checksum] changes this value
/// and breaks the test — which is the point. Every key already issued would
/// stop working, so that has to be a deliberate act, not a side effect.
const String activationTestVector = 'KIU-7F3K-X4T8';

/// Whether [input] is a well-formed key whose checksum matches its body.
///
/// Tolerant about presentation, strict about content: case, surrounding
/// whitespace and internal spaces are all normalized away, because the common
/// path is a user pasting a key out of a Telegram message. Anything that is not
/// then exactly `KIU-<4>-<4>` over [activationAlphabet] is rejected.
bool isValidActivationKey(String input) {
  final parts = normalizeActivationKey(input).split('-');
  if (parts.length != 3) return false;
  final [prefix, body, checksum] = parts;
  if (prefix != _prefix) return false;
  if (body.length != _blockLength || checksum.length != _blockLength) {
    return false;
  }
  if (!_isAlphabet(body) || !_isAlphabet(checksum)) return false;
  return _checksum(body) == checksum;
}

/// Uppercases [input] and strips every character that cannot appear in a key,
/// so spaces, non-breaking spaces and stray punctuation from a copy-paste do
/// not reach the comparison.
String normalizeActivationKey(String input) {
  final buffer = StringBuffer();
  for (final unit in input.toUpperCase().codeUnits) {
    final char = String.fromCharCode(unit);
    if (char == '-' || activationAlphabet.contains(char) || _isLetter(char)) {
      buffer.write(char);
    }
  }
  return buffer.toString();
}

bool _isLetter(String char) =>
    char.codeUnitAt(0) >= 0x41 && char.codeUnitAt(0) <= 0x5A;

bool _isAlphabet(String value) =>
    value.split('').every(activationAlphabet.contains);

/// FNV-1a over `body + salt`, folded down to [_blockLength] characters of
/// [activationAlphabet].
///
/// Written out rather than pulled from `crypto`: the package is not a
/// dependency, this is not a security primitive, and the Python generator has
/// to reproduce it byte for byte. Masked to 32 bits on every step so Dart's
/// native ints and Python's unbounded ones stay in agreement.
String _checksum(String body) {
  var hash = 0x811c9dc5;
  for (final unit in '$body$_salt'.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final buffer = StringBuffer();
  for (var i = 0; i < _blockLength; i++) {
    buffer.write(activationAlphabet[hash % activationAlphabet.length]);
    hash = hash ~/ activationAlphabet.length;
  }
  return buffer.toString();
}

/// The key for [body], for tests and for cross-checking the Python generator.
String activationKeyFor(String body) {
  final normalized = body.toUpperCase();
  return '$_prefix-$normalized-${_checksum(normalized)}';
}
