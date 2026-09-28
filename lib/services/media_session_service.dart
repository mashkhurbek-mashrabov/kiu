import 'package:flutter/services.dart';

/// Channel to the native media session (`LessonPlaybackService`) and PiP.
///
/// Separate from the shared `platformChannel` on purpose: `AndroidApkInstaller`
/// already owns that channel's one `setMethodCallHandler`, and a second handler
/// would silently replace it. The "one channel" rule exists for the WorkManager
/// isolate; media is bound to `MainActivity`, the only place the WebView lives.
///
/// Dart → native: `update` (play state, title, labels) and `clear`.
/// Native → Dart: `command` (one of [mediaCommands]) and `pipChanged` (bool).
const MethodChannel mediaChannel = MethodChannel('com.mashkhurbek.kiu/media');

/// The only actions a native `command` may run on the page.
const Set<String> mediaCommands = {'play', 'pause', 'rewind', 'forward'};
