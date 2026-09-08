import 'dart:convert';

String playbackRateScript(double rate) {
  final encodedRate = jsonEncode(rate.clamp(0.25, 4.0));
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
