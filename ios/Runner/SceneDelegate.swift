import Flutter
import OSLog
import UIKit

private let log = Logger(subsystem: "com.mashkhurbek.kiu", category: "scene")

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    log.info("openURL \(URLContexts.map(\.url.absoluteString), privacy: .public)")
    #if DEBUG
      // `xcrun simctl openurl booted "kiu://debug-call?seconds=10&title=...&url=..."`
      // rings a test lesson call -- the iOS twin of the adb recipe in CLAUDE.md.
      // Compiled out of release builds, so no link can arm an alarm there.
      for context in URLContexts where context.url.host == "debug-call" {
        let items = URLComponents(url: context.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let seconds = value("seconds").flatMap(TimeInterval.init) ?? 10
        Task {
          let ok = await LessonCalls.ringTest(
            title: value("title") ?? "Arabic Grammar",
            meetingUrl: value("url"),
            in: seconds
          )
          log.info("debug call armed=\(ok, privacy: .public) in \(seconds, privacy: .public)s")
        }
      }
    #endif
  }
}
