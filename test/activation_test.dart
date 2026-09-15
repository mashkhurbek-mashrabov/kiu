import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/activation.dart';

void main() {
  group('isValidActivationKey', () {
    test('accepts the pinned test vector for its own user ID', () {
      // Guards against the checksum, salt or alphabet changing silently. Any
      // such change invalidates every key already issued, so it has to be a
      // deliberate edit to this expectation -- not a side effect.
      //
      // tool/generate_activation_key.py asserts the same pairing.
      expect(activationTestUserId, 'K7M29X');
      expect(activationTestVector, 'KIU-K7M29X-D7XL');
      expect(activationKeyFor(activationTestUserId), activationTestVector);
      expect(
        isValidActivationKey(activationTestVector, activationTestUserId),
        isTrue,
      );
    });

    test('rejects a key issued for a different install', () {
      // The whole point of the change: a key shared with someone else does not
      // unlock their copy.
      expect(isValidActivationKey(activationTestVector, 'A2B3C4'), isFalse);
      final other = activationKeyFor('A2B3C4');
      expect(isValidActivationKey(other, activationTestUserId), isFalse);
      expect(isValidActivationKey(other, 'A2B3C4'), isTrue);
    });

    test('rejects pre-2.1.0 unbound keys', () {
      // 2.0.0 shipped KIU-7F3K-X4T8 and friends, valid on any install. The
      // salt bump plus the length change must leave them all dead.
      expect(
        isValidActivationKey('KIU-7F3K-X4T8', activationTestUserId),
        isFalse,
      );
      expect(isValidActivationKey('KIU-7F3K-X4T8', '7F3K'), isFalse);
    });

    test('rejects a body whose checksum does not match', () {
      expect(isValidActivationKey('KIU-K7M29X-D7XM', 'K7M29X'), isFalse);
      expect(isValidActivationKey('KIU-K7M29X-AAAA', 'K7M29X'), isFalse);
    });

    test('tolerates case, whitespace and the display dashes', () {
      expect(isValidActivationKey('  kiu-k7m29x-d7xl  ', 'K7M29X'), isTrue);
      expect(isValidActivationKey('Kiu-K7m29X-d7Xl', 'K7M29X'), isTrue);
      expect(isValidActivationKey('KIU - K7M29X - D7XL', 'K7M29X'), isTrue);
      // The page shows the ID grouped, so that form must work as the argument.
      expect(isValidActivationKey(activationTestVector, 'K7M-29X'), isTrue);
      expect(isValidActivationKey(activationTestVector, 'k7m-29x'), isTrue);
    });

    test('rejects malformed keys', () {
      for (final input in [
        '',
        '   ',
        'KIU',
        'KIU-K7M29X',
        'KIU-K7M29X-D7XL-EXTRA',
        'K7M29X-D7XL',
        'ABC-K7M29X-D7XL',
        'KIU-K7M29-D7XL',
        'KIU-K7M29XX-D7XL',
        'KIU-K7M29X-D7X',
      ]) {
        expect(
          isValidActivationKey(input, 'K7M29X'),
          isFalse,
          reason: 'expected $input to be rejected',
        );
      }
    });

    test('rejects an unusable user ID', () {
      // A missing or corrupt ID must fail closed rather than accept anything.
      for (final id in ['', '   ', 'K7M29', 'K7M29XX', 'K7M2OX', 'k7m29!']) {
        expect(
          isValidActivationKey(activationTestVector, id),
          isFalse,
          reason: 'expected user ID $id to be rejected',
        );
      }
    });

    test('every generated key validates for its own ID', () {
      // Sweeps the alphabet rather than trusting one example: catches a
      // checksum that happens to work for the pinned vector but not in general.
      for (final char in activationAlphabet.split('')) {
        final id = '$char$char$char$char$char$char';
        expect(
          isValidActivationKey(activationKeyFor(id), id),
          isTrue,
          reason: 'expected a key for $id to validate',
        );
      }
    });
  });

  group('generateUserId', () {
    test('returns an ID of the right shape', () {
      final id = generateUserId();
      expect(id.length, userIdLength);
      expect(id.split('').every(activationAlphabet.contains), isTrue);
    });

    test('does not repeat itself', () {
      // Not a randomness proof -- just catches a constant or an off-by-one that
      // would hand every install the same ID, which would undo the binding.
      final ids = {for (var i = 0; i < 200; i++) generateUserId()};
      expect(ids.length, greaterThan(190));
    });

    test('is deterministic for a seeded Random', () {
      expect(generateUserId(Random(42)), generateUserId(Random(42)));
    });
  });

  group('formatUserId', () {
    test('groups an ID for display', () {
      expect(formatUserId('K7M29X'), 'K7M-29X');
    });

    test('round-trips back through validation', () {
      final id = generateUserId();
      expect(
        isValidActivationKey(activationKeyFor(id), formatUserId(id)),
        isTrue,
      );
    });

    test('leaves an unexpected length alone', () {
      expect(formatUserId('ABC'), 'ABC');
    });
  });
}
