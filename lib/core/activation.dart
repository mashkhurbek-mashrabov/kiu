/// Activation keys for the gated extras, bound to one install.
///
/// Every install mints a random [userIdLength]-character **user ID** on first
/// launch. A key is `KIU-<userId>-<checksum>`, where the checksum is derived
/// from that ID plus [_salt] — so [isValidActivationKey] only accepts a key
/// whose body matches *this* install's ID. A key issued for one device is
/// rejected everywhere else, which is what stops a key handed to one student
/// from unlocking the feature for a whole group chat.
///
/// The exchange is manual and offline: the hidden page shows the user their ID,
/// they send it to the developer, and the developer mints a key for it with
/// `tool/generate_activation_key.py --id <id>`.
///
/// **This is a soft gate, not a security boundary.** [_salt] ships inside the
/// APK, so anyone who decompiles the app can mint a key for their own ID; R8
/// raises that bar but does not move it. Nothing secret sits behind the check —
/// the gated action runs against the user's own LMS session. What binding buys
/// is that a *shared* key is useless, not that the scheme is unbreakable.
///
/// It also buys no revocation: without a server there is no way to switch an
/// issued key off. Note too that the ID lives in app storage, so a reinstall or
/// a "clear app data" mints a new one and the old key stops working — that user
/// has to ask for another.
///
/// `tool/generate_activation_key.py` reimplements [_checksum] exactly. The two
/// must stay in lockstep — [activationTestVector] is pinned in both so a change
/// to one without the other fails the test suite rather than silently
/// invalidating every key already handed out.
library;

import 'dart:math';

/// Mixed into the checksum so a user ID alone does not determine it.
///
/// Bumped to `v2` when keys became ID-bound: together with the binding itself,
/// this makes every unbound 2.0.0 key invalid, which is deliberate.
const String _salt = 'kiu-activation-2026-v2';

/// Characters a key or user ID may use, in checksum-index order.
///
/// Deliberately missing `O`, `0`, `I` and `1`: these get read off one screen and
/// retyped into another, and those are the pairs that get misread.
const String activationAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Fixed prefix, so a key is recognizable as one when pasted into a chat.
const String _prefix = 'KIU';

/// Length of the per-install user ID, which is also a key's body.
///
/// Six characters over a 32-character alphabet is ~1.07 billion combinations —
/// far beyond any collision risk at this app's scale, and still short enough to
/// read aloud or retype if the copy fails.
const int userIdLength = 6;

/// Length of the checksum block.
const int _checksumLength = 4;

/// A known-good pairing, asserted by both the Dart tests and the Python
/// generator.
///
/// Any edit to [_salt], [activationAlphabet] or [_checksum] changes this value
/// and breaks the test — which is the point. Every key already issued would stop
/// working, so that has to be a deliberate act, not a side effect.
const String activationTestUserId = 'K7M29X';
const String activationTestVector = 'KIU-K7M29X-D7XL';

/// Whether [input] is a well-formed key issued for [userId].
///
/// [userId] is required rather than optional on purpose: making it so forces
/// every call site through the compiler, and no path can validate a key without
/// knowing which install it is for.
///
/// Tolerant about presentation, strict about content: case, surrounding
/// whitespace and internal spaces are all normalized away, because the common
/// path is a user pasting a key out of a Telegram message. Anything that is not
/// then exactly `KIU-<userId>-<checksum>` over [activationAlphabet] is rejected.
bool isValidActivationKey(String input, String userId) {
  final normalizedId = normalizeActivationKey(userId).replaceAll('-', '');
  if (normalizedId.length != userIdLength || !_isAlphabet(normalizedId)) {
    return false;
  }
  final parts = normalizeActivationKey(input).split('-');
  if (parts.length != 3) return false;
  final [prefix, body, checksum] = parts;
  if (prefix != _prefix) return false;
  if (body.length != userIdLength || checksum.length != _checksumLength) {
    return false;
  }
  if (!_isAlphabet(body) || !_isAlphabet(checksum)) return false;
  // The binding: a key minted for another install fails here, before the
  // checksum is even consulted.
  if (body != normalizedId) return false;
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
    value.isNotEmpty && value.split('').every(activationAlphabet.contains);

/// A fresh user ID for this install.
///
/// [random] defaults to [Random.secure]; tests inject a seeded [Random] to pin
/// a value. Not a secret — it is displayed to the user and sent over Telegram —
/// but it should be unguessable enough that nobody mints a key for someone
/// else's install by chance.
String generateUserId([Random? random]) {
  final source = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < userIdLength; i++) {
    buffer.write(activationAlphabet[source.nextInt(activationAlphabet.length)]);
  }
  return buffer.toString();
}

/// `K7M29X` rendered as `K7M-29X`, for display only.
///
/// Grouping halves the chance of a dropped character when the user reads it
/// aloud or retypes it. [isValidActivationKey] and the generator both strip
/// dashes, so either form can be pasted back.
String formatUserId(String id) =>
    id.length == userIdLength ? '${id.substring(0, 3)}-${id.substring(3)}' : id;

/// FNV-1a over `userId + salt`, folded down to [_checksumLength] characters of
/// [activationAlphabet].
///
/// Written out rather than pulled from `crypto`: the package is not a
/// dependency, this is not a security primitive, and the Python generator has
/// to reproduce it byte for byte. Masked to 32 bits on every step so Dart's
/// native ints and Python's unbounded ones stay in agreement.
String _checksum(String userId) {
  var hash = 0x811c9dc5;
  for (final unit in '$userId$_salt'.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  final buffer = StringBuffer();
  for (var i = 0; i < _checksumLength; i++) {
    buffer.write(activationAlphabet[hash % activationAlphabet.length]);
    hash = hash ~/ activationAlphabet.length;
  }
  return buffer.toString();
}

/// The key for [userId], for tests and for cross-checking the Python generator.
String activationKeyFor(String userId) {
  final normalized = normalizeActivationKey(userId).replaceAll('-', '');
  return '$_prefix-$normalized-${_checksum(normalized)}';
}
