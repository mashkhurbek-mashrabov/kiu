@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/core/constants.dart';
import 'package:kiu/services/update_service.dart';

/// Exercises the real GitHub endpoint. Tagged `live` and excluded from the
/// default run (see dart_test.yaml) so the suite stays offline and
/// deterministic; run with `flutter test --tags live` to check the contract
/// against the actual repository.
void main() {
  test('the live endpoint answers and parses', () async {
    final checker = GitHubUpdateChecker();
    final result = await checker.check(installedBuild: 18, abi: 2);
    checker.close();

    expect(
      result.answered,
      isTrue,
      reason: 'the public repo must answer unauthenticated at $latestReleaseApiUrl',
    );
  });

  test('a released asset URL passes the host allowlist', () async {
    final checker = GitHubUpdateChecker();
    // Build 0 is below anything ever published, so any marked release is
    // offered and its asset URL can be checked against the allowlist.
    final result = await checker.check(installedBuild: 0, abi: 2);
    checker.close();

    final update = result.update;
    if (update == null) {
      // No release carries a marker yet, which is the correct answer rather
      // than a failure. The offline suite covers the parsed path.
      return;
    }
    expect(isGitHubReleaseAsset(Uri.parse(update.apkUrl)), isTrue);
    expect(update.apkUrl, endsWith('-arm64-v8a.apk'));
    expect(update.apkSize, greaterThan(0));
  });
}
