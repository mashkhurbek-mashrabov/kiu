#!/usr/bin/env python3
"""Generate a KIU activation key for one user's install.

Keys are bound to an install. Each app generates a random 6-character user ID
on first launch and shows it on the hidden activation page; the user sends that
ID over Telegram, and this script mints the key for it. The key is rejected on
every other install, so a key shared in a group chat is useless to everyone but
its owner.

This must stay byte-for-byte equivalent to ``isValidActivationKey`` in
``lib/core/activation.dart``. ``TEST_VECTOR`` is pinned in both files and
checked on every run; if it fails, the two implementations have drifted and
every key already issued is at risk.

Usage::

    python3 tool/generate_activation_key.py --id K7M-29X
    python3 tool/generate_activation_key.py --id K7M29X   # dashes optional

Developer tooling only. Nothing in lib/ may reference this file.
"""

from __future__ import annotations

import argparse
import sys

# Mirrors _salt in lib/core/activation.dart. Bumped to v2 when keys became
# install-bound, which is what invalidated every unbound 2.0.0 key.
SALT = "kiu-activation-2026-v2"

# Mirrors activationAlphabet. No O/0/I/1 -- these get read off a screen and
# retyped, and those are the pairs that get misread.
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

PREFIX = "KIU"
USER_ID_LENGTH = 6
CHECKSUM_LENGTH = 4

# Mirrors activationTestUserId / activationTestVector in activation.dart.
TEST_USER_ID = "K7M29X"
TEST_VECTOR = "KIU-K7M29X-D7XL"


def checksum(user_id: str) -> str:
    """FNV-1a over ``user_id + SALT``, folded onto ALPHABET.

    Masked to 32 bits at every step so Python's unbounded ints match Dart's
    native ones.
    """
    value = 0x811C9DC5
    for char in user_id + SALT:
        value = (value ^ ord(char)) & 0xFFFFFFFF
        value = (value * 0x01000193) & 0xFFFFFFFF
    out = []
    for _ in range(CHECKSUM_LENGTH):
        out.append(ALPHABET[value % len(ALPHABET)])
        value //= len(ALPHABET)
    return "".join(out)


def normalize(user_id: str) -> str:
    """Uppercase and strip the display dashes, so ``K7M-29X`` is accepted.

    The app shows the ID grouped for readability; users paste back whichever
    form they happen to copy.
    """
    return user_id.upper().replace("-", "").replace(" ", "")


def key_for(user_id: str) -> str:
    """The key for ``user_id``, which works only on that install."""
    user_id = normalize(user_id)
    if len(user_id) != USER_ID_LENGTH:
        raise ValueError(
            f"user ID must be {USER_ID_LENGTH} characters, got {user_id!r} "
            f"({len(user_id)})"
        )
    invalid = sorted(set(user_id) - set(ALPHABET))
    if invalid:
        raise ValueError(
            f"user ID uses characters outside the alphabet: {''.join(invalid)}\n"
            f"allowed: {ALPHABET}\n"
            f"note O/0 and I/1 are excluded -- check for a misread character"
        )
    return f"{PREFIX}-{user_id}-{checksum(user_id)}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a KIU activation key for one user's install.",
        epilog="Keys validate offline and only on the install they were made for.",
    )
    parser.add_argument(
        "--id",
        dest="user_id",
        required=True,
        help="the user ID from the app's activation page, e.g. K7M-29X",
    )
    args = parser.parse_args()

    # Guards against the Dart and Python hashes drifting apart. A mismatch means
    # keys minted here would be rejected by the app.
    if key_for(TEST_USER_ID) != TEST_VECTOR:
        print(
            f"ERROR: test vector mismatch.\n"
            f"  expected {TEST_VECTOR}\n"
            f"  got      {key_for(TEST_USER_ID)}\n"
            f"This generator and lib/core/activation.dart have diverged.",
            file=sys.stderr,
        )
        return 1

    try:
        print(key_for(args.user_id))
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
