#!/usr/bin/env python3
"""Generate KIU activation keys.

A key is ``KIU-<body>-<checksum>``. The app validates it offline by recomputing
the checksum from the body and the salt, so every correctly-formed body is a
distinct valid key -- hand a different one to each person and a leaked key is
traceable back to whoever it was issued to.

This must stay byte-for-byte equivalent to ``isValidActivationKey`` in
``lib/core/activation.dart``. ``TEST_VECTOR`` is pinned in both files and
checked on every run; if it fails, the two implementations have drifted and
every key already issued is at risk.

Usage::

    python3 tool/generate_activation_key.py               # one random key
    python3 tool/generate_activation_key.py --count 10    # ten keys
    python3 tool/generate_activation_key.py --body 7F3K   # a specific body

Developer tooling only. Nothing in lib/ may reference this file.
"""

from __future__ import annotations

import argparse
import secrets
import sys

# Mirrors _salt in lib/core/activation.dart.
SALT = "kiu-activation-2026-v1"

# Mirrors activationAlphabet. No O/0/I/1 -- keys get read off a screen and
# retyped, and those are the pairs that get misread.
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

PREFIX = "KIU"
BLOCK_LENGTH = 4

# Mirrors activationTestVector in lib/core/activation.dart.
TEST_VECTOR = "KIU-7F3K-X4T8"


def checksum(body: str) -> str:
    """FNV-1a over ``body + SALT``, folded onto ALPHABET.

    Masked to 32 bits at every step so Python's unbounded ints match Dart's
    native ones.
    """
    value = 0x811C9DC5
    for char in body + SALT:
        value = (value ^ ord(char)) & 0xFFFFFFFF
        value = (value * 0x01000193) & 0xFFFFFFFF
    out = []
    for _ in range(BLOCK_LENGTH):
        out.append(ALPHABET[value % len(ALPHABET)])
        value //= len(ALPHABET)
    return "".join(out)


def key_for(body: str) -> str:
    """The full key for ``body``."""
    body = body.upper()
    if len(body) != BLOCK_LENGTH:
        raise ValueError(f"body must be {BLOCK_LENGTH} characters, got {body!r}")
    invalid = sorted(set(body) - set(ALPHABET))
    if invalid:
        raise ValueError(
            f"body uses characters outside the alphabet: {''.join(invalid)}\n"
            f"allowed: {ALPHABET}"
        )
    return f"{PREFIX}-{body}-{checksum(body)}"


def random_body() -> str:
    """A random body, drawn from the same alphabet the app accepts."""
    return "".join(secrets.choice(ALPHABET) for _ in range(BLOCK_LENGTH))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate KIU activation keys.",
        epilog="Keys validate offline; no server is involved.",
    )
    parser.add_argument(
        "--body",
        help=f"use this {BLOCK_LENGTH}-character body instead of a random one",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=1,
        help="how many random keys to generate (default: 1)",
    )
    args = parser.parse_args()

    # Guards against the Dart and Python hashes drifting apart. A mismatch means
    # keys minted here would be rejected by the app.
    if key_for("7F3K") != TEST_VECTOR:
        print(
            f"ERROR: test vector mismatch.\n"
            f"  expected {TEST_VECTOR}\n"
            f"  got      {key_for('7F3K')}\n"
            f"This generator and lib/core/activation.dart have diverged.",
            file=sys.stderr,
        )
        return 1

    if args.body:
        try:
            print(key_for(args.body))
        except ValueError as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 1
        return 0

    if args.count < 1:
        print("ERROR: --count must be at least 1", file=sys.stderr)
        return 1

    # A body could repeat across runs; dedupe within this one so a batch handed
    # out to N people really is N distinct keys.
    seen: set[str] = set()
    while len(seen) < args.count:
        seen.add(random_body())
    for body in sorted(seen):
        print(key_for(body))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
