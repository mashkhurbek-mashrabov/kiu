import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// The iOS side of `com.mashkhurbek.kiu/media`, the counterpart of Android's
/// `LessonPlaybackService`: one Now Playing session that feeds the Lock
/// Screen, Control Center, AirPods and CarPlay, whose commands come back to
/// Dart as `command` and run on the page through `mediaCommandScript`.
///
/// Dart → native: `update` {playing, title, position, duration, speed} and
/// `clear`. Native → Dart: `command` (play | pause | rewind | forward).
///
/// The `.playback` audio session is what lets a lesson keep playing with the
/// screen locked and lets WebKit's own Picture in Picture keep running when
/// the user leaves the app; it needs the `audio` background mode.
final class MediaSessionPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var commandsInstalled = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.mashkhurbek.kiu/media",
      binaryMessenger: registrar.messenger()
    )
    let instance = MediaSessionPlugin(channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      update(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "clear":
      clear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func update(_ args: [String: Any]) {
    activateAudioSession()
    installCommandsOnce()
    let playing = args["playing"] as? Bool ?? false
    let speed = (args["speed"] as? NSNumber)?.doubleValue ?? 1
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: args["title"] as? String ?? "",
      MPMediaItemPropertyArtist: "KIU",
      MPNowPlayingInfoPropertyElapsedPlaybackTime: (args["position"] as? NSNumber)?.doubleValue ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
    ]
    if let duration = (args["duration"] as? NSNumber)?.doubleValue, duration.isFinite, duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    if let icon = UIImage(named: "AppIcon") ?? Self.appIcon() {
      info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: icon.size) { _ in icon }
    }
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = info
    center.playbackState = playing ? .playing : .paused
  }

  private func clear() {
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
  }

  private func activateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    guard session.category != .playback else { return }
    // .moviePlayback keeps speech intelligible at 1.5-2x, which is how most
    // lessons are watched.
    try? session.setCategory(.playback, mode: .moviePlayback)
    try? session.setActive(true)
  }

  private func installCommandsOnce() {
    guard !commandsInstalled else { return }
    commandsInstalled = true
    let commands = MPRemoteCommandCenter.shared()
    let send: (String) -> MPRemoteCommandHandlerStatus = { [weak self] action in
      self?.channel.invokeMethod("command", arguments: action)
      return .success
    }
    commands.playCommand.addTarget { _ in send("play") }
    commands.pauseCommand.addTarget { _ in send("pause") }
    commands.togglePlayPauseCommand.addTarget { _ in
      send(MPNowPlayingInfoCenter.default().playbackState == .playing ? "pause" : "play")
    }
    // Same 10 s steps as `mediaCommandScript` on Android.
    commands.skipBackwardCommand.preferredIntervals = [10]
    commands.skipForwardCommand.preferredIntervals = [10]
    commands.skipBackwardCommand.addTarget { _ in send("rewind") }
    commands.skipForwardCommand.addTarget { _ in send("forward") }
    // Headphone and car next/previous map onto the same skips.
    commands.nextTrackCommand.addTarget { _ in send("forward") }
    commands.previousTrackCommand.addTarget { _ in send("rewind") }
  }

  private static func appIcon() -> UIImage? {
    guard
      let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
      let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
      let files = primary["CFBundleIconFiles"] as? [String],
      let name = files.last
    else { return nil }
    return UIImage(named: name)
  }
}
