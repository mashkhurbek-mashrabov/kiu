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

/// Reads the user's course level out of the site's own navigation.
///
/// The level is per-user and a level-less `/profile/my-courses` does not
/// redirect, so the page is the only source for it. Every logged-in page ships
/// the same nav, so this runs on each trusted load and needs no URL allowlist.
///
/// Reports over the bridge rather than returning a value, matching
/// [pullToRefreshScript]. Staying silent when nothing matches is meaningful:
/// Dart leaves the cached level alone, so a logged-out page — which has no such
/// link — never clears a good value.
String courseLevelScript() => '''
(() => {
  const pattern = /^\\/(?:uz|ru)\\/profile\\/my-courses\\/([1-9]\\d*)\\/?\$/;
  for (const link of document.querySelectorAll('a.nav-link[href]')) {
    const url = new URL(link.getAttribute('href'), location.href);
    const match =
      url.origin === location.origin && url.pathname.match(pattern);
    if (match) {
      return KiuBridge.postMessage(JSON.stringify({
        type: 'courseLevel', level: Number(match[1]),
      }));
    }
  }
})();
''';

/// Reports the playing lesson video's position so it can be resumed later.
///
/// Native players: `timeupdate`/`pause`/`ended` do not bubble, but a
/// *capturing* listener on `document` still sees them, which also covers a
/// `<video>` mounted after load without needing an observer.
///
/// The Russian course plays in a cross-origin Rutube iframe that exposes no
/// `<video>`; its player posts `player:currentTime` to this window instead,
/// and `player:changeState` stands in for the pause event. Only messages whose origin is exactly `https://rutube.ru` are read.
///
/// Only the position crosses the bridge -- Dart pairs it with its own idea of
/// the current URL. Throttled to one report per 5 s of movement, plus one on
/// pause; `ended` reports 0 so a finished video restarts from the beginning.
///
/// The same listeners also send an unthrottled `videoState` on every play
/// state change or seek, which drives the system media session (notification,
/// lockscreen, Bluetooth/car and the PiP window's controls).
String videoProgressScript() => '''
(() => {
  if (window.__kiuVideoProgressBound) return 'present';
  window.__kiuVideoProgressBound = true;
  let lastSent = null;
  let rutubeTime = null;
  let rutubeDuration = null;
  let rutubePlaying = false;
  const send = (seconds, force) => {
    if (typeof seconds !== 'number' || !isFinite(seconds) || seconds < 0) return;
    if (!force && lastSent !== null && Math.abs(seconds - lastSent) < 5) return;
    lastSent = seconds;
    KiuBridge.postMessage(JSON.stringify({type: 'videoProgress', seconds}));
  };
  const sendState = (playing, seconds, duration, rate) => {
    if (typeof seconds !== 'number' || !isFinite(seconds) || seconds < 0) seconds = 0;
    KiuBridge.postMessage(JSON.stringify({
      type: 'videoState', playing, seconds,
      duration: typeof duration === 'number' && isFinite(duration) ? duration : 0,
      rate: typeof rate === 'number' && isFinite(rate) ? rate : 1,
    }));
  };
  const onMedia = (event) => {
    const video = event.target;
    if (!(video instanceof HTMLMediaElement)) return;
    if (event.type !== 'timeupdate') {
      sendState(!video.paused && !video.ended, video.currentTime,
        video.duration, video.playbackRate);
    }
    if (event.type === 'ended') return send(0, true);
    if (event.type === 'timeupdate' || event.type === 'pause') {
      send(video.currentTime, event.type === 'pause');
    }
  };
  ['timeupdate', 'pause', 'ended', 'play', 'playing', 'seeked'].forEach((name) =>
    document.addEventListener(name, onMedia, true));
  window.addEventListener('message', (event) => {
    if (event.origin !== 'https://rutube.ru') return;
    let message = event.data;
    try {
      if (typeof message === 'string') message = JSON.parse(message);
    } catch (error) {
      return;
    }
    if (!message || !message.data) return;
    if (message.type === 'player:currentTime') {
      rutubeTime = message.data.time ?? message.data.currentTime;
      send(rutubeTime, false);
    } else if (message.type === 'player:durationChange') {
      rutubeDuration = message.data.duration;
      sendState(rutubePlaying, rutubeTime, rutubeDuration, 1);
    } else if (message.type === 'player:changeState') {
      rutubePlaying = message.data.state === 'playing';
      sendState(rutubePlaying, rutubeTime, rutubeDuration, 1);
      if (message.data.state === 'paused') send(rutubeTime, true);
    }
  });
  return 'bound';
})();
''';

/// Runs a system media-session command (notification, lockscreen, car, PiP)
/// on the lesson video: `play`, `pause`, `rewind` or `forward` (10 s).
///
/// Only those four actions exist; anything else is a no-op here, and Dart
/// never forwards anything else in the first place.
String mediaCommandScript(String action) {
  final encodedAction = jsonEncode(action);
  return '''
(() => {
  const action = $encodedAction;
  const step = action === 'forward' ? 10 : action === 'rewind' ? -10 : 0;
  const video = document.querySelector('#video_player, video');
  if (video) {
    if (action === 'play') video.play().catch(() => {});
    else if (action === 'pause') video.pause();
    else if (step) video.currentTime = Math.max(0, video.currentTime + step);
    return action;
  }
  const frame = document.querySelector('iframe[src*="rutube.ru"]');
  if (!frame) return 'missing';
  const command = (type, data) => frame.contentWindow?.postMessage(
    JSON.stringify({type, data}), '*');
  if (action === 'play') command('player:play', {});
  else if (action === 'pause') command('player:pause', {});
  else if (step) command('player:relativelySeek', {time: step});
  return action;
})();
''';
}

/// Makes the lesson video fill the page while the app is in picture-in-picture,
/// so the tiny window shows the video rather than a corner of the lesson page.
///
/// CSS on a class toggled on `<html>` rather than `requestFullscreen()`, which
/// needs a user gesture that PiP entry never provides. Idempotent.
String pipLayoutScript(bool on) {
  final encodedOn = jsonEncode(on);
  return '''
(() => {
  const on = $encodedOn;
  const id = 'kiu-pip-style';
  if (!document.getElementById(id)) {
    const style = document.createElement('style');
    style.id = id;
    style.textContent = `html.kiu-pip .plyr,
      html.kiu-pip video,
      html.kiu-pip iframe[src*="rutube.ru"] {
        position: fixed !important;
        inset: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        max-width: none !important;
        z-index: 2147483647 !important;
        background: #000 !important;
      }`;
    (document.head || document.documentElement).appendChild(style);
  }
  document.documentElement.classList.toggle('kiu-pip', on);
  return on ? 'pip' : 'page';
})();
''';
}

/// Seeks the lesson video to [seconds] and starts it.
///
/// Polls because neither player is ready at `onPageFinished`: the native one
/// needs metadata (`readyState >= 1`) before a seek sticks, and the Rutube
/// iframe drops commands sent before its player loads, so those are resent
/// every tick until the player itself reports both a position near the target
/// and a `playing` state. The seek alone is not enough: Rutube can accept it
/// and still drop a `play` that arrived too early, leaving the lesson paused.
/// Gives up after ~30 s.
String resumeVideoScript(double seconds) {
  final encodedSeconds = jsonEncode(seconds);
  return '''
(() => {
  const target = $encodedSeconds;
  let ticks = 0;
  let timer = null;
  let seeked = false;
  let playing = false;
  const command = (frame, type, data) => frame.contentWindow?.postMessage(
    JSON.stringify({type, data}), '*');
  const onMessage = (event) => {
    if (event.origin !== 'https://rutube.ru') return;
    let message = event.data;
    try {
      if (typeof message === 'string') message = JSON.parse(message);
    } catch (error) {
      return;
    }
    if (!message || !message.data) return;
    if (message.type === 'player:currentTime') {
      const time = message.data.time ?? message.data.currentTime;
      if (typeof time === 'number' && time >= target - 5) seeked = true;
    } else if (message.type === 'player:changeState') {
      playing = message.data.state === 'playing';
    }
    if (seeked && playing) stop();
  };
  const stop = () => {
    clearInterval(timer);
    window.removeEventListener('message', onMessage);
  };
  window.addEventListener('message', onMessage);
  timer = setInterval(() => {
    if (++ticks > 60) return stop();
    const video = document.querySelector('#video_player, video');
    if (video) {
      // Without preload the metadata never arrives on its own; play() fetches
      // it, and the seek lands on the next tick.
      if (video.readyState < 1) return void video.play().catch(() => {});
      video.currentTime = target;
      video.play().catch(() => {});
      return stop();
    }
    const frame = document.querySelector('iframe[src*="rutube.ru"]');
    if (!frame) return;
    if (!seeked) command(frame, 'player:setCurrentTime', {time: target});
    command(frame, 'player:play', {});
  }, 500);
  return 'polling';
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
