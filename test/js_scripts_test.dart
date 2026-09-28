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

  test('video iframe fix gives the player a 16:9 box and stays idempotent', () {
    final script = videoIframeFixScript();
    expect(script, contains('#lesson-content iframe'));
    expect(script, contains('aspect-ratio: 16 / 9'));
    expect(script, contains('width: 100%'));
    // Re-injection on a reload must not stack duplicate <style> nodes.
    expect(script, contains("getElementById(id)"));
  });

  test('mark watched script carries both LMS events and token support', () {
    final script = markWatchedScript('request-1');
    expect(script, contains('lessonVideoIsEnded'));
    expect(script, contains('lessonVideoIsPlaying'));
    expect(script, contains('time_spent: 9999'));
    expect(script, contains('playback_token'));
    expect(script, contains('request-1'));
  });

  test('video progress script reads native and rutube players only', () {
    final script = videoProgressScript();
    expect(script, contains('__kiuVideoProgressBound'));
    expect(script, contains("type: 'videoProgress'"));
    expect(script, contains("event.origin !== 'https://rutube.ru'"));
    expect(script, contains('player:currentTime'));
    // Capturing, because media events do not bubble to `document`.
    expect(script, contains('document.addEventListener(name, onMedia, true)'));
  });

  test('resume script seeks both players and only trusts rutube', () {
    final script = resumeVideoScript(303.5);
    expect(script, contains('const target = 303.5'));
    expect(script, contains('player:setCurrentTime'));
    expect(script, contains("event.origin !== 'https://rutube.ru'"));
    expect(script, contains('readyState < 1'));
    // A reported seek alone is not done: Rutube may have dropped the play.
    expect(script, contains('if (seeked && playing) stop();'));
  });

  test('video progress script also reports play state for the session', () {
    final script = videoProgressScript();
    expect(script, contains("type: 'videoState'"));
    expect(script, contains('player:changeState'));
    expect(script, contains('player:durationChange'));
    // Rutube is still read from its exact origin only.
    expect(script, contains("event.origin !== 'https://rutube.ru'"));
  });

  test('media command script drives both players', () {
    final forward = mediaCommandScript('forward');
    expect(forward, contains('const action = "forward"'));
    expect(forward, contains('#video_player, video'));
    expect(forward, contains('player:relativelySeek'));
    expect(mediaCommandScript('pause'), contains('player:pause'));
    expect(mediaCommandScript('play'), contains('player:play'));
    // The action is JSON-encoded, so it can never break out of the string.
    expect(mediaCommandScript('"); alert(1); ("'), contains(r'\"'));
  });

  test('pip layout script toggles one class and one stylesheet', () {
    final on = pipLayoutScript(true);
    expect(on, contains('const on = true'));
    expect(on, contains("classList.toggle('kiu-pip', on)"));
    expect(on, contains('iframe[src*="rutube.ru"]'));
    expect(on, contains('getElementById(id)'));
    expect(pipLayoutScript(false), contains('const on = false'));
  });
}
