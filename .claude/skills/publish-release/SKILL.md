---
name: publish-release
description: Publish a new KIU version to GitHub Releases - bump the version, build split APKs, tag, create the release with its update marker, and upload the APKs. Use when asked to "publish a release", "ship 1.5.5", "cut a release", or "release a new version".
---

# Publish a KIU release

KIU ships outside the Play Store. The in-app updater reads
`releases/latest` from GitHub, so a release is only real once the APKs are
attached **and** the body carries a valid marker. A release without both is
invisible to every installed app.

## Before starting

Confirm with the user:

- **The version number.** Never guess it. Semantic: fixes are a patch bump.
- **Whether the update is mandatory.** Defaults to true; an optional release
  must say `mandatory=false` explicitly.

Then check the working tree is clean and on `main`, and that the previous
release's work is actually merged.

## 1. Bump the version

`pubspec.yaml` — bump both parts:

```yaml
version: 1.5.5+24
```

**The build number must increase on every release and must never be reused.**
Android rejects a duplicate on upgrade. Keep it under 999: `--split-per-abi`
adds `1000 * abi` to it, and the updater relies on `code % 1000`.

This goes in **its own commit**, after the feature work:

```
chore(release): 1.5.5+24
```

Do not fold it into the feature commit — this has been slipped several times
and needed a `git reset --soft` to correct.

## 2. Verify before building

```bash
export PATH="/home/dev/.cache/kiu-flutter-3.47.2/flutter/bin:$PATH"
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

All three must pass. Do not proceed past a failure.

## 3. Build and stage the APKs

```bash
flutter build apk --release --split-per-abi
```

Flutter prints `Gradle build failed to produce an .apk file` at the end. **This
is expected** — it looks for an armeabi-v7a APK the project deliberately does
not build. The arm64 and x86_64 APKs are valid; check they exist.

Copy them to `dist/` under the exact name the updater's asset matcher expects:

```bash
for abi in arm64-v8a x86_64; do
  cp "build/app/outputs/flutter-apk/app-$abi-release.apk" "dist/KIU-<version>+<build>-$abi.apk"
done
```

The `-<abi>.apk` suffix is what `_selectAsset` in
`lib/services/update_service.dart` matches on. A mistyped name means the app
finds the release, finds no asset for its ABI, and silently offers nothing.

Confirm the version codes are `2<build>` and `4<build>` (`apkanalyzer` is not
on `PATH`; use the full path):

```bash
/home/dev/Android/cmdline-tools/latest/bin/apkanalyzer manifest print \
  dist/KIU-<version>+<build>-x86_64.apk | grep -oE 'versionCode="[0-9]+"'
```

## 4. Tag and push

```bash
git tag -a v<version> -m "KIU <version>"
git push origin main
git push origin v<version>
```

## 5. Write the release body

Summarize `.release-notes/<version>.md` per the project convention: merge
bullets describing one feature, drop churn that never reached a user, order
features → changes → fixes. Keep it user-facing — no file paths or commit refs.

End the body with the marker, which must be a **trailing HTML comment**:

```
<!-- kiu-update: build=24 mandatory=true -->
```

- `build` is the **pubspec** build number (24), never the APK's code (2024/4024).
- `mandatory` defaults to true when absent.
- `minBuild=N` optionally forces the update for anyone below N.

GitHub strips HTML comments when rendering, so it stays invisible to users while
the API still returns it in the raw `body`. Verified.

## 6. Create the release and upload

The token is at `~/.config/gh_kiu_token` (fine-grained, `Contents: write`).
Read it into a variable — never echo it.

```bash
T=$(cat ~/.config/gh_kiu_token)
```

Create the release (`make_latest: "true"` unless backfilling an older version,
which must use `"false"` so it does not displace the current one):

```bash
curl -s -X POST -H "Authorization: Bearer $T" \
  -H "Accept: application/vnd.github+json" -d @/tmp/rel.json \
  https://api.github.com/repos/mashkhurbek-mashrabov/kiu/releases
```

Then upload both APKs to the returned release id. The name must be URL-encoded —
the `+` in the filename breaks an unencoded query parameter:

```bash
curl -s -X POST -H "Authorization: Bearer $T" \
  -H "Content-Type: application/vnd.android.package-archive" \
  --data-binary @"dist/$name" \
  "https://uploads.github.com/repos/mashkhurbek-mashrabov/kiu/releases/$ID/assets?name=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$name")"
```

Replacing an asset requires deleting the old one first — GitHub rejects a
duplicate name.

## 7. Verify what the app will actually see

```bash
curl -s -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/mashkhurbek-mashrabov/kiu/releases/latest
```

Check: correct tag, marker present with the right build, both APKs listed.

## 8. Overwrite the local notes

Replace `.release-notes/<version>.md` with the summarized text that shipped, so
the file matches the published release. `.release-notes/` is local-only and must
never be committed.

## Testing an update end to end

To watch a real upgrade, install the **previous** release and let the app find
the new one:

```bash
adb install -r "dist/KIU-<previous>-x86_64.apk"
adb shell appops set com.mashkhurbek.kiu REQUEST_INSTALL_PACKAGES allow
adb shell am start -n com.mashkhurbek.kiu/.MainActivity
```

The gate should appear on launch. Tap Update; the installer prompt follows in
seconds.

To test a *newer* build than anything published, temporarily `PATCH` the
release body's marker upward, run the test, then **restore it**. Leaving a
bumped marker live makes every installed app demand an update that does not
exist.

## Gotchas that have actually bitten

- **The unauthenticated API is 60 requests/hour per IP.** Repeated verification
  curls exhaust it, after which the app correctly reports "no answer" and shows
  no gate — which looks exactly like a broken updater. Check
  `api.github.com/rate_limit` before concluding anything is wrong.
- **The app under test is the one doing the installing.** A fix to the install
  path only takes effect from the release that *contains* it, so upgrading
  *into* that version still uses the old code.
- **Every APK is currently debug-signed.** `android/key.properties` does not
  exist, so Gradle falls back to the shared Flutter debug key. The user has
  been informed and has declined a release keystore — do not re-raise it
  unprompted. If a keystore is ever added, every existing user must uninstall
  once, because Android rejects an in-place upgrade across a key change.
