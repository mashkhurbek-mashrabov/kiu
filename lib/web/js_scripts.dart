import 'dart:convert';

String playbackRateScript(double rate) {
  final encodedRate = jsonEncode(rate.clamp(0.5, 4.0));
  return '''
(() => {
  const rate = $encodedRate;
  const apply = (root = document) => {
    root.querySelectorAll?.('video').forEach((video) => {
      video.defaultPlaybackRate = rate;
      video.playbackRate = rate;
      if (!video.dataset.kiuSpeedBound) {
        video.dataset.kiuSpeedBound = '1';
        ['loadedmetadata', 'play', 'ratechange'].forEach((eventName) => {
          video.addEventListener(eventName, () => {
            if (Math.abs(video.playbackRate - window.__kiuPlaybackRate) > 0.001) {
              video.defaultPlaybackRate = window.__kiuPlaybackRate;
              video.playbackRate = window.__kiuPlaybackRate;
            }
          });
        });
      }
    });
  };
  window.__kiuPlaybackRate = rate;
  apply();
  if (!window.__kiuSpeedObserver) {
    window.__kiuSpeedObserver = new MutationObserver((records) => {
      records.forEach((record) => record.addedNodes.forEach((node) => {
        if (node.nodeType === Node.ELEMENT_NODE) apply(node);
      }));
    });
    window.__kiuSpeedObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
    });
  }
  return document.querySelectorAll('video').length;
})();
''';
}

/// Drives the LMS theme the same way the site's own `theme-script.js` does:
/// `localStorage.darkMode` is the source of truth and the site applies it as a
/// `dark`/`light` class on `<html>` on every load. Writing both directly (in
/// place of clicking `#dark-mode-toggle`) also survives navigation, since the
/// site re-reads localStorage before first paint.
String siteThemeScript(bool dark) {
  final encodedDark = jsonEncode(dark);
  return '''
(() => {
  const dark = $encodedDark;
  try {
    window.localStorage.setItem('darkMode', dark ? 'enabled' : 'disabled');
  } catch (error) {
    // Storage can be blocked; the class below still themes this page.
  }
  const root = document.documentElement;
  root.classList.toggle('dark', dark);
  root.classList.toggle('light', !dark);
  // The header keeps two buttons; `activate` marks the one still available,
  // so the icon for the mode we just left is the visible one.
  const darkToggle = document.getElementById('dark-mode-toggle');
  const lightToggle = document.getElementById('light-mode-toggle');
  if (!darkToggle || !lightToggle) return 'applied';
  darkToggle.classList.toggle('activate', !dark);
  lightToggle.classList.toggle('activate', dark);
  return 'synced';
})();
''';
}

/// Sizes the Russian course's video iframe, which the site ships without a
/// height and so collapses to a few pixels tall. A stylesheet rather than
/// inline styles on the element: the iframe is mounted after `onPageFinished`
/// on some lessons, and CSS applies to it whenever it appears, so this needs no
/// re-run and no observer. Idempotent — re-injecting replaces the same node.
String videoIframeFixScript() => '''
(() => {
  const id = 'kiu-video-iframe-fix';
  if (document.getElementById(id)) return 'present';
  const style = document.createElement('style');
  style.id = id;
  style.textContent = `#lesson-content iframe {
    display: block;
    width: 100%;
    height: auto;
    aspect-ratio: 16 / 9;
  }`;
  (document.head || document.documentElement).appendChild(style);
  return 'injected';
})();
''';

/// Pull-to-refresh, driven by the page's own touch events.
///
/// A Flutter `RefreshIndicator` around the WebView never fires: the platform
/// view swallows the gesture, so Flutter sees no overscroll. Instead the page
/// reports a downward drag that starts at the top of the scroller, and Dart
/// owns the indicator and the reload. Only the report crosses the bridge —
/// nothing here reloads or navigates on its own.
///
/// The drag must begin with the scroller already at 0; a fling that happens to
/// reach the top mid-gesture must not trigger, which is why the offset is
/// latched on `touchstart` rather than read during the move.
String pullToRefreshScript({int thresholdPx = 90}) {
  final encodedThreshold = jsonEncode(thresholdPx);
  return '''
(() => {
  if (window.__kiuPullBound) return 'present';
  window.__kiuPullBound = true;
  const threshold = $encodedThreshold;
  const scrollTop = () => window.scrollY
    || document.documentElement.scrollTop
    || document.body.scrollTop
    || 0;
  let startY = null;
  let armed = false;
  const send = (phase, distance) => KiuBridge.postMessage(JSON.stringify({
    type: 'pullRefresh', phase, distance,
  }));
  document.addEventListener('touchstart', (event) => {
    armed = event.touches.length === 1 && scrollTop() <= 0;
    startY = armed ? event.touches[0].clientY : null;
  }, {passive: true});
  document.addEventListener('touchmove', (event) => {
    if (!armed || startY === null) return;
    // A second finger mid-gesture is a pinch-zoom, not a pull.
    if (event.touches.length !== 1 || scrollTop() > 0) {
      armed = false;
      send('cancel', 0);
      return;
    }
    const distance = event.touches[0].clientY - startY;
    if (distance > 0) send('move', Math.min(distance, threshold * 2));
  }, {passive: true});
  // Always reports, even when the gesture never armed: Dart clears its
  // indicator on this message, and a silent return here is what leaves a
  // half-drawn spinner on screen when a pull is interrupted rather than
  // finished (the finger leaves the WebView, or the system steals the
  // gesture). Reporting an unarmed release is harmless — Dart only reloads
  // when the distance it already saw passed the threshold.
  const end = () => {
    const wasArmed = armed;
    armed = false;
    startY = null;
    send(wasArmed ? 'end' : 'cancel', 0);
  };
  document.addEventListener('touchend', end, {passive: true});
  document.addEventListener('touchcancel', end, {passive: true});
  return 'bound';
})();
''';
}

String markWatchedScript(String requestId) {
  final encodedRequestId = jsonEncode(requestId);
  return '''
(() => {
  const requestId = $encodedRequestId;
  const send = (ok, code, payload = null) => KiuBridge.postMessage(JSON.stringify({
    type: 'markWatchedResult', requestId, ok, code, payload
  }));
  try {
    if (typeof window.jQuery === 'undefined') return send(false, 'jquery_missing');
    if (typeof lesson_id === 'undefined') return send(false, 'lesson_id_missing');
    if (!document.querySelector('video')) return send(false, 'video_missing');
    const data = (method, extra = {}) => {
      const result = {method, lesson_id: lesson_id, ...extra};
      if (typeof playback_token !== 'undefined' && playback_token) {
        result.playback_token = playback_token;
      }
      return result;
    };
    const post = (body) => new Promise((resolve, reject) => {
      window.jQuery.post('/api', body, resolve).fail((xhr) => reject(
        new Error('HTTP ' + (xhr.status || 'error'))
      ));
    });
    Promise.all([
      post(data('lessonVideoIsEnded')),
      post(data('lessonVideoIsPlaying', {time_spent: 9999})),
    ]).then((values) => send(true, 'completed', values))
      .catch((error) => send(false, 'request_failed', {message: error.message}));
  } catch (error) {
    send(false, 'exception', {message: String(error)});
  }
})();
''';
}
