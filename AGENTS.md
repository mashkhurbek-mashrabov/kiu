# Repository Guidelines

**[CLAUDE.md](CLAUDE.md) is the canonical guide for working in this repo.** It
covers project structure, commands, style, testing, the non-obvious invariants
("Rules"), security constraints, and the settled lesson-call constraints. Read
it first; this file previously duplicated it almost entirely and drifted.

See also:

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit: layers, sync flow,
  the background-isolate boundary, trust boundaries, and the lesson-call path.
- [README.md](README.md) — setup, verification, and release builds.

## Quick reference

The Flutter SDK is **not on `PATH`**:

```sh
export PATH="/home/dev/.cache/kiu-flutter-3.47.2/flutter/bin:$PATH"
```

Before any delivery, all three must pass:

```sh
flutter analyze && flutter test && dart format --output=none --set-exit-if-changed lib test
```

Native widget, alarm, or lesson-call changes additionally require installing on
an API-33 emulator and verifying by hand — R8 is enabled, and a stripped
reflective entry point fails silently rather than crashing. See CLAUDE.md.
