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
