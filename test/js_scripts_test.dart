import 'package:flutter_test/flutter_test.dart';
import 'package:kiu/web/js_scripts.dart';

void main() {
  test('playback script installs persistence hooks and clamps rate', () {
    final script = playbackRateScript(9);
    expect(script, contains('const rate = 4'));
    expect(script, contains('MutationObserver'));
    expect(script, contains('loadedmetadata'));
    expect(script, contains('ratechange'));
  });

  test('playback script enforces 0.5x minimum', () {
    expect(playbackRateScript(0.25), contains('const rate = 0.5'));
  });

  test('site theme script writes the storage key the LMS reads on load', () {
    final dark = siteThemeScript(true);
    expect(dark, contains('const dark = true'));
    expect(
      dark,
      contains("setItem('darkMode', dark ? 'enabled' : 'disabled')"),
    );
    expect(dark, contains("classList.toggle('dark', dark)"));
    expect(dark, contains("classList.toggle('light', !dark)"));
    // The site's own buttons stay in sync, and `activate` marks the mode you
    // can switch to, not the active one.
    expect(dark, contains("darkToggle.classList.toggle('activate', !dark)"));
    expect(dark, contains("lightToggle.classList.toggle('activate', dark)"));
    expect(siteThemeScript(false), contains('const dark = false'));
  });

  test('mark watched script carries both LMS events and token support', () {
    final script = markWatchedScript('request-1');
    expect(script, contains('lessonVideoIsEnded'));
    expect(script, contains('lessonVideoIsPlaying'));
    expect(script, contains('time_spent: 9999'));
    expect(script, contains('playback_token'));
    expect(script, contains('request-1'));
  });
}
