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

Flutter is the global Homebrew install, already on `PATH`
(`/opt/homebrew/bin/flutter`) — no PATH prefix needed.

Before any delivery, all three must pass:

```sh
flutter analyze && flutter test && dart format --output=none --set-exit-if-changed lib test
```

Native widget, alarm, or lesson-call changes additionally require installing on
the `pixel_api35` emulator (API 35) and verifying by hand — R8 is enabled, and
a stripped reflective entry point fails silently rather than crashing. See
CLAUDE.md.
