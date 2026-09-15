import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/activation.dart';

void main() {
  group('isValidActivationKey', () {
    test('accepts the pinned test vector', () {
      // Guards against the checksum, salt or alphabet changing silently. Any
      // such change invalidates every key already issued, so it has to be a
      // deliberate edit to this expectation -- not a side effect.
      //
      // tool/generate_activation_key.py asserts the same value.
      expect(activationTestVector, 'KIU-7F3K-X4T8');
      expect(isValidActivationKey(activationTestVector), isTrue);
      expect(activationKeyFor('7F3K'), activationTestVector);
    });

    test('rejects a body whose checksum does not match', () {
      expect(isValidActivationKey('KIU-7F3K-X4T9'), isFalse);
      expect(isValidActivationKey('KIU-7F3J-X4T8'), isFalse);
    });

    test('tolerates case and surrounding whitespace', () {
      expect(isValidActivationKey('  kiu-7f3k-x4t8  '), isTrue);
      expect(isValidActivationKey('Kiu-7f3K-x4T8'), isTrue);
    });

    test('tolerates spaces inside a pasted key', () {
      expect(isValidActivationKey('KIU - 7F3K - X4T8'), isTrue);
    });

    test('rejects malformed input', () {
      for (final input in [
        '',
        '   ',
        'KIU',
        'KIU-7F3K',
        'KIU-7F3K-X4T8-EXTRA',
        '7F3K-X4T8',
        'ABC-7F3K-X4T8',
        'KIU-7F3-X4T8',
        'KIU-7F3KK-X4T8',
      ]) {
        expect(
          isValidActivationKey(input),
          isFalse,
          reason: 'expected $input to be rejected',
        );
      }
    });

    test('rejects the ambiguous characters the alphabet excludes', () {
      // O/0 and I/1 are not in the alphabet, so a key containing them cannot
      // be valid however its checksum comes out.
      for (final char in ['O', '0', 'I', '1']) {
        expect(activationAlphabet.contains(char), isFalse);
        expect(isValidActivationKey('KIU-${char}F3K-X4T8'), isFalse);
      }
    });

    test('every generated key validates', () {
      // Sweeps the alphabet rather than trusting one example: catches a
      // checksum that happens to work for the pinned vector but not in general.
      for (final char in activationAlphabet.split('')) {
        final key = activationKeyFor('$char$char$char$char');
        expect(
          isValidActivationKey(key),
          isTrue,
          reason: 'expected $key to validate',
        );
      }
    });

    test('a different body yields a different key', () {
      // A checksum that ignored its input would still pass every test above.
      final keys = activationAlphabet
          .split('')
          .map((char) => activationKeyFor('A${char}23'))
          .toSet();
      expect(keys.length, activationAlphabet.length);
    });
  });
}
