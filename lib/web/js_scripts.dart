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
/// Injected at page start as well as at `onPageFinished`, so it must be
/// idempotent per document (`__kiuResumeBound`) and tolerate a player that
/// does not exist yet: it polls every 100 ms for up to ~30 s.
///
/// Native player: `currentTime` set before metadata arrives becomes the
/// default playback start position, so `play()` buffers at the target instead
/// of buffering at 0 and then again after a seek. Later ticks re-assert the
/// seek once metadata is in, for a player that ignored the early one.
///
/// The Rutube iframe drops commands sent before its player loads, so those are
/// resent until the player itself reports both a position near the target and
/// a `playing` state. The seek alone is not enough: Rutube can accept it and
/// still drop a `play` that arrived too early, leaving the lesson paused.
String resumeVideoScript(double seconds) {
  final encodedSeconds = jsonEncode(seconds);
  return '''
(() => {
  if (window.__kiuResumeBound) return 'present';
  window.__kiuResumeBound = true;
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
  const tick = () => {
    if (++ticks > 300) return stop();
    const video = document.querySelector('#video_player, video');
    if (video) {
      if (video.readyState < 1) {
        video.currentTime = target;
        return void video.play().catch(() => {});
      }
      if (Math.abs(video.currentTime - target) > 2) video.currentTime = target;
      video.play().catch(() => {});
      return stop();
    }
    const frame = document.querySelector('iframe[src*="rutube.ru"]');
    if (!frame) return;
    if (!seeked) command(frame, 'player:setCurrentTime', {time: target});
    command(frame, 'player:play', {});
  };
  timer = setInterval(tick, 100);
  tick();
  return 'polling';
})();
''';
}

/// Seconds of watch time the LMS credits per `lessonVideoIsPlaying` ping; it
/// silently clamps anything larger to this.
const markWatchedPingSeconds = 30;

/// Marks the open lesson's video as watched, the way the LMS's own player
/// (`course.js`) reports it: claim the playback session, then send watch-time
/// pings until the server says the lesson is done.
///
/// The server counts cumulative `time_spent` against the video duration and
/// caps each ping at [markWatchedPingSeconds], so one big ping is not enough.
/// Pings are bounded by the duration so a server that never says "done"
/// cannot loop forever. The session is released afterwards so the video can
/// still be played on another device.
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
    const video = document.querySelector('#video_player, video');
    if (!video) return send(false, 'video_missing');
    let token = typeof playbackToken === 'string' ? playbackToken : '';
    if (!token) {
      try { token = sessionStorage.getItem('lesson_playback_token_' + lesson_id) || ''; } catch (e) {}
    }
    if (!token) return send(false, 'token_missing');
    const known = typeof lesson_video_progress !== 'undefined' && lesson_video_progress
      ? Number(lesson_video_progress.duration) : NaN;
    const duration = Math.floor(known > 0 ? known : video.duration);
    if (!(duration > 0)) return send(false, 'duration_missing');
    const step = $markWatchedPingSeconds;
    const maxPings = Math.ceil(duration / step) + 5;
    const base = {lesson_id: lesson_id, playback_token: token};
    const post = (body) => new Promise((resolve, reject) => {
      window.jQuery.post('/api', body, resolve).fail((xhr) => reject(
        new Error('HTTP ' + (xhr.status || 'error'))
      ));
    });
    const release = () => post({method: 'releaseLessonVideoSession', ...base}).catch(() => {});
    const finished = (r) => r && (r.status === true || (r.progress && r.progress.done === true));
    (async () => {
      const claim = await post({method: 'changeLessonVideoChecked', ...base});
      if (claim && claim.session_invalid === true) return send(false, 'session_blocked');
      const ranges = JSON.stringify([[0, duration]]);
      let playing = null;
      for (let i = 0; i < maxPings; i++) {
        playing = await post({method: 'lessonVideoIsPlaying', ...base, time_spent: step, ranges});
        if (playing && playing.session_invalid === true) return send(false, 'session_blocked');
        if (!playing || playing.ok === false) {
          await release();
          return send(false, 'rejected', playing && playing.progress);
        }
        if (finished(playing)) break;
      }
      await post({method: 'lessonVideoIsEnded', ...base}).catch(() => {});
      await release();
      if (finished(playing)) return send(true, 'completed', playing.progress);
      send(false, 'not_counted', playing && playing.progress);
    })().catch((error) => {
      release();
      send(false, 'request_failed', {message: error.message});
    });
  } catch (error) {
    send(false, 'exception', {message: String(error)});
  }
})();
''';
}

/// The lesson video's file URL and the lesson's name, as a JSON string
/// `{"src": ..., "title": ...}`.
///
/// The source is the native player's `currentSrc`, or its first `<source>`
/// before the player has picked one. The page `<title>` is the same generic
/// site name on every lesson, so the name comes from the course-contents link
/// that points at this lesson, then the course heading.
///
/// Run with `runJavaScriptReturningResult`, which evaluates in the main frame
/// only: the URL is never taken from a bridge message, which the Rutube frame
/// could also send. Dart still validates it with `isLessonVideoFile`.
String videoSourceScript() => '''
(() => {
  const video = document.querySelector('#video_player, video');
  const src = video
    ? video.currentSrc || video.querySelector('source')?.src || ''
    : '';
  const lesson = location.pathname.split('/').filter(Boolean).slice(2, 4).join('/');
  const clean = (node) => (node?.textContent || '').replace(/\\s+/g, ' ').trim();
  const link = [...document.querySelectorAll('.panel-title1 a[href]')]
    .find((a) => a.pathname.includes('/' + lesson + '/'));
  const title = clean(link) || clean(document.querySelector('h4')) || document.title;
  return JSON.stringify({src, title: title.slice(0, 200)});
})();
''';

/// Points the lesson's own player at a downloaded copy of its video, so it
/// keeps playing with no internet. The page and the player stay as they are;
/// only the `<video>` source changes.
///
/// Keeps the position and the playing state, so it can also run mid-lesson
/// when a download finishes. Idempotent: does nothing once on [url].
String localVideoSourceScript(String url) {
  final encodedUrl = jsonEncode(url);
  return '''
(() => {
  const url = $encodedUrl;
  const video = document.querySelector('#video_player, video');
  if (!video) return 'missing';
  if (video.getAttribute('src') === url) return 'present';
  const time = video.currentTime;
  const playing = !video.paused && !video.ended;
  video.src = url;
  if (time > 0) {
    video.addEventListener('loadedmetadata', () => { video.currentTime = time; },
      {once: true});
  }
  if (playing) video.play().catch(() => {});
  return 'swapped';
})();
''';
}

/// The course names on a "my courses" page, as a JSON string
/// `{"<course id>": "<name>", ...}`.
///
/// Lesson pages carry no clean course name, so it is learned here: each course
/// card's title link points at `<lang>/my-course/<course>/<lesson>/video`. The
/// link also holds a lesson-count badge and the subject in `<small>`, which are
/// dropped. Dart validates the result before storing it.
String courseNamesScript() => '''
(() => {
  const names = {};
  document.querySelectorAll('h3.title a[href]').forEach((link) => {
    const id = link.pathname.split('/').filter(Boolean)[2];
    if (!/^[1-9][0-9]*\$/.test(id || '')) return;
    const copy = link.cloneNode(true);
    copy.querySelectorAll('span, small, br').forEach((node) => node.remove());
    const name = copy.textContent.replace(/[\\s()]+/g, ' ').trim();
    if (name && !names[id]) names[id] = name.slice(0, 200);
  });
  return JSON.stringify(names);
})();
''';
