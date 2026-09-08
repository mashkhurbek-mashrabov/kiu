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

  test('mark watched script carries both LMS events and token support', () {
    final script = markWatchedScript('request-1');
    expect(script, contains('lessonVideoIsEnded'));
    expect(script, contains('lessonVideoIsPlaying'));
    expect(script, contains('time_spent: 9999'));
    expect(script, contains('playback_token'));
    expect(script, contains('request-1'));
  });
}
