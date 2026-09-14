---
name: feature-branch
description: Start a feature or fix branch off main and merge it back when the work is done - branch naming, the pre-merge checks, opening the PR, and cleaning up. Use when asked to "start a feature", "create a branch", "merge this branch", "open a PR", or when beginning work that is not a one-line fix.
---

# Feature branches in KIU

`main` is the release branch: every tag is cut from it and the updater serves
what it builds. Work lands there through a branch and a pull request, never by
committing to `main` directly.

## Starting

Confirm the branch name with the user if the scope is not obvious. Naming
follows what the repo already uses:

- `feat/<slug>` — new behaviour (`feat/lesson-calls`, `feat/pull-to-refresh`)
- `fix/<slug>` — a defect (`fix/background-access-refresh`)
- `chore/<slug>` — tooling, docs, cleanup (`chore/codebase-review`)

Short, hyphenated, describes the change and not the file touched.

**Always branch from an up-to-date `main`:**

```bash
git checkout main
git pull origin main
git checkout -b feat/<slug>
```

Do not skip the pull. `main` has been behind `origin/main` before, and
branching from a stale copy produces a merge that silently reverts work.

Verify it took — `git checkout -b` has appeared to succeed while leaving HEAD
elsewhere:

```bash
git branch --show-current
```

## While working

Commit in logical units, Conventional Commits, imperative present, subject under
72 characters:

```
fix(sync): accept LMS schedule container id
```

Explain *why* in the body when the reason is not obvious from the diff. The
project's own commit history is the style reference.

**The version bump is never part of a feature commit.** It belongs in its own
`chore(release): <version>` commit at release time — see the `publish-release`
skill. This has been slipped repeatedly and needed `git reset --soft` to fix.

## Before merging

All three must pass, and a failure stops the merge:

```bash
export PATH="/home/dev/.cache/kiu-flutter-3.47.2/flutter/bin:$PATH"
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Beyond the suite, check what the change touches:

- **Native widget, lesson calls, alarms, notifications** — R8 strips
  manifest-named classes silently. Install a *release* build on a device and
  exercise the path; a debug build proves nothing about R8.
- **`.arb` edits** — run `flutter gen-l10n`. The generated files are committed
  and must not drift.
- **Anything user-visible** — add a bullet to `.release-notes/<version>.md`.
  That file is local-only and must never be committed.

## Opening the PR

Every feature so far has merged through a GitHub PR, which is what produces the
`Merge pull request #N from ...` commits in the history. Keep that.

```bash
git push -u origin feat/<slug>
```

**The `gh` CLI is not installed, and the token at `~/.config/gh_kiu_token`
cannot create pull requests** — it is scoped to `Contents: write` and returns
`403 Resource not accessible by personal access token` on the PR endpoint.
Verified.

So open the PR in the browser:

```
https://github.com/mashkhurbek-mashrabov/kiu/compare/main...feat/<slug>
```

The PR body should describe user-visible behaviour, list the verification
commands actually run, and attach screenshots for UI or widget changes.

If the user wants PRs created programmatically, they need to add
**Pull requests: write** to the token — do not assume it has been added.

## Merging

The user merges the PR on GitHub. Afterwards:

```bash
git checkout main
git pull origin main
git branch -d feat/<slug>
git push origin --delete feat/<slug>
```

`git branch -d` (not `-D`) is deliberate: it refuses to delete a branch whose
work is not actually merged, which is the check worth having.

## Local merge fallback

Only when the user explicitly asks to skip the PR:

```bash
git checkout main
git pull origin main
git merge --no-ff feat/<slug>
git push origin main
```

`--no-ff` keeps the branch visible in history, matching how the PR merges look.

## Gotchas that have actually bitten

- **`git checkout -b` appearing to succeed without switching.** Commits then
  land on `main` instead of the branch. Confirm with
  `git branch --show-current` before starting work.
- **`git add -A` sweeping in `pubspec.yaml`** during a release, folding the
  version bump into a feature commit. Stage deliberately, or check
  `git show --stat HEAD` before pushing.
- **A branch that looks unmerged but is not.** `feat/decline-dodge` was merged
  as PR #8 while the local branch still existed, which made it look outstanding.
  Check `git log --oneline main --grep=<slug>` before assuming work is pending.
- **Local `main` behind `origin/main`.** Always pull before branching or
  merging.
