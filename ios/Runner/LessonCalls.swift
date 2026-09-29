import AlarmKit
import AppIntents
import Foundation
import OSLog
import SwiftUI
import UIKit
import UserNotifications

/// iOS lesson calls: the counterpart of `LessonCallAlarms.kt` + the Android
/// call screen.
///
/// iOS cannot put an app's own screen up by itself, so a call is rung one of
/// two ways:
/// - an AlarmKit alarm (iOS 26+, once the user allows it): breaks through
///   silent mode and Focus, takes the whole Lock Screen, offers Join/Dismiss;
/// - otherwise a time-sensitive notification at the lesson start with the same
///   Join/Dismiss actions -- iOS 17-25, a denied AlarmKit prompt, and the
///   Simulator, which has no Clock app and denies AlarmKit outright.
///
/// The schedule is the same `calls` JSON array the Android alarms read, which
/// `HomeLessonWidgetGateway` writes into the App Group, so re-arming also works
/// from the background sync engine, like the Android design (see CLAUDE.md,
/// "Lesson calls").
private let log = Logger(subsystem: "com.mashkhurbek.kiu", category: "calls")

enum LessonCalls {
  /// Must match `iosAppGroupId` in `lib/core/platform.dart`.
  static let appGroup = "group.com.mashkhurbek.kiu"
  /// Mirrors `trustedHost` in `lib/core/constants.dart`.
  static let trustedHost = "uz.do-kazankiu.ru"
  /// AlarmKit refuses past a per-app limit, and notifications share iOS's 64
  /// pending slots with reminders; only the soonest calls matter, and the next
  /// sync re-arms the rest long before they arrive.
  static let maxArmed = 16
  /// The notification fallback rings each call up to [maxRepeats] times, so
  /// it shares the 64 pending slots with reminders (capped at 48 in Dart):
  /// 5 calls x 3 rings = 15 leaves room.
  static let maxNotificationCalls = 5
  static let maxRepeats = 3
  /// A notification sound may run at most 30 s; the ringtone is 29 s, and each
  /// repeat starts where the previous one ends.
  static let ringLength: TimeInterval = 30
  /// Notification category and id prefix of the fallback call.
  static let category = "KIU_LESSON_CALL"
  static let joinAction = "KIU_CALL_JOIN"
  private static let idPrefix = "kiu-call-"

  /// Calls work on every supported iOS: AlarmKit or the notification fallback.
  static var available: Bool { true }

  static var alarmKitAuthorized: Bool {
    if #available(iOS 26.0, *) {
      return AlarmManager.shared.authorizationState == .authorized
    }
    return false
  }

  /// AlarmKit alone, for first-launch onboarding: true only when real alarm
  /// calls are allowed, never for the notification fallback.
  static func requestAlarmKitAuthorization() async -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    switch AlarmManager.shared.authorizationState {
    case .authorized: return true
    case .denied: return false
    default:
      return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
    }
  }

  /// Asks for AlarmKit where it exists, then makes sure notifications are
  /// allowed for the fallback. True when either way can ring.
  static func requestAuthorization() async -> Bool {
    if #available(iOS 26.0, *) {
      switch AlarmManager.shared.authorizationState {
      case .authorized: return true
      case .notDetermined:
        if (try? await AlarmManager.shared.requestAuthorization()) == .authorized { return true }
      default: break
      }
    }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return true
    case .notDetermined:
      return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    default: return false
    }
  }

  /// Replaces every armed call with the current `calls` payload and returns
  /// how many were armed. An alarm ringing right now is left alone: a sync
  /// landing mid-ring must not silence the call the user is looking at.
  @discardableResult
  static func rearm() async -> Int {
    await clearNotificationCalls()
    if #available(iOS 26.0, *) {
      let manager = AlarmManager.shared
      for alarm in (try? manager.alarms) ?? [] where alarm.state != .alerting {
        try? manager.cancel(id: alarm.id)
      }
    }
    let payload = CallPayload.load()
    let limit = alarmKitAuthorized ? maxArmed : maxNotificationCalls
    let upcoming = payload.calls.filter { $0.startDate > Date() }.prefix(limit)
    var armed = 0
    for call in upcoming where await arm(call, labels: payload) {
      armed += 1
    }
    return armed
  }

  /// Rings once, [seconds] from now, with sample content. Debug builds only:
  /// it is how the call path is exercised without waiting for a real lesson,
  /// like the `adb shell am broadcast` recipe for Android in CLAUDE.md.
  static func ringTest(title: String, meetingUrl: String?, in seconds: TimeInterval) async -> Bool {
    guard await requestAuthorization() else {
      log.info("test call not authorized")
      return false
    }
    let call = LessonCall(
      key: "debug",
      title: title,
      displayStart: "",
      start: (Date().timeIntervalSince1970 + seconds) * 1000,
      meetingUrl: meetingUrl
    )
    return await arm(call, labels: CallPayload.load())
  }

  /// One call, through AlarmKit when it is allowed, else as a notification.
  private static func arm(_ call: LessonCall, labels: CallPayload) async -> Bool {
    if #available(iOS 26.0, *), AlarmManager.shared.authorizationState == .authorized {
      do {
        _ = try await AlarmManager.shared.schedule(
          id: UUID(),
          configuration: configuration(for: call, labels: labels)
        )
        log.info("armed alarm \(call.key, privacy: .public)")
        return true
      } catch {
        // One bad entry (or the system limit) must not strand the rest,
        // mirroring the reminder reconciler's per-item failure handling.
        log.error("could not arm \(call.key, privacy: .public): \(String(describing: error), privacy: .public)")
        return false
      }
    }
    return await armNotification(call, labels: labels)
  }

  /// Rings like a call as far as notifications can: the 29-second KIU
  /// ringtone, repeated back to back for the ring duration, grouped in one
  /// thread so the Lock Screen shows a single call rather than a stack.
  private static func armNotification(_ call: LessonCall, labels: CallPayload) async -> Bool {
    let center = UNUserNotificationCenter.current()
    registerCategory(labels: labels)
    let target = joinTarget(for: call.meetingUrl)
    let repeats = min(maxRepeats, max(1, Int((labels.ringSeconds / ringLength).rounded(.up))))
    var armed = false
    for ring in 0..<repeats {
      let content = UNMutableNotificationContent()
      content.title = call.title
      content.subtitle = labels.incoming
      content.body = call.displayStart
      content.sound = UNNotificationSound(named: UNNotificationSoundName("kiu_ring.caf"))
      content.categoryIdentifier = category
      content.threadIdentifier = idPrefix + call.key
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = 1
      content.userInfo = [
        "target": target,
        "key": call.key,
        "title": call.title,
        "time": call.displayStart,
      ]
      let fireDate = call.startDate.addingTimeInterval(Double(ring) * ringLength)
      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: fireDate
      )
      let request = UNNotificationRequest(
        identifier: "\(idPrefix)\(call.key)#\(ring)",
        content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      )
      do {
        try await center.add(request)
        armed = true
      } catch {
        log.error("could not post call \(call.key, privacy: .public): \(String(describing: error), privacy: .public)")
      }
    }
    if armed { log.info("armed notification call \(call.key, privacy: .public) x\(repeats, privacy: .public)") }
    return armed
  }

  /// Stops a call that has been answered or declined: its later rings are
  /// withdrawn and the ones already shown are cleared.
  static func cancelRepeats(for key: String) {
    let center = UNUserNotificationCenter.current()
    let prefix = idPrefix + key + "#"
    center.getPendingNotificationRequests { pending in
      center.removePendingNotificationRequests(
        withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
      )
    }
    center.getDeliveredNotifications { delivered in
      center.removeDeliveredNotifications(
        withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
      )
    }
  }

  /// A call coming due while KIU is open: the full call screen instead of a
  /// banner. Later rings of the same call are swallowed while it rings.
  @MainActor
  static func present(_ notification: UNNotification) {
    let info = notification.request.content.userInfo
    guard let key = info["key"] as? String else { return }
    if CallScreen.shared.ringingKey == key { return }
    let labels = CallPayload.load()
    CallScreen.shared.present(
      key: key,
      title: info["title"] as? String ?? notification.request.content.title,
      time: info["time"] as? String ?? "",
      incoming: labels.incoming,
      answer: labels.answer,
      decline: labels.decline,
      target: info["target"] as? String ?? "kiu://open?homeWidget=1",
      ringSeconds: labels.ringSeconds
    )
  }

  private static func clearNotificationCalls() async {
    let center = UNUserNotificationCenter.current()
    let ids = await center.pendingNotificationRequests()
      .map(\.identifier)
      .filter { $0.hasPrefix(idPrefix) }
    center.removePendingNotificationRequests(withIdentifiers: ids)
  }

  /// Join opens the app (`.foreground`); Dismiss is the system's own clear.
  /// Re-registered on every arm so the button follows the app language.
  private static func registerCategory(labels: CallPayload) {
    let join = UNNotificationAction(
      identifier: joinAction,
      title: labels.answer,
      options: [.foreground],
      icon: UNNotificationActionIcon(systemImageName: "video.fill")
    )
    let callCategory = UNNotificationCategory(
      identifier: category,
      actions: [join],
      intentIdentifiers: [],
      options: [.customDismissAction]
    )
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { existing in
      let others = existing.filter { $0.identifier != category }
      center.setNotificationCategories(others.union([callCategory]))
    }
  }

  /// Handles a tap on a fallback call or its Join button; false when the
  /// response is not a KIU call, so the caller passes it on.
  @MainActor
  static func handle(_ response: UNNotificationResponse) -> Bool {
    let content = response.notification.request.content
    log.info("notification response \(response.actionIdentifier, privacy: .public) category \(content.categoryIdentifier, privacy: .public)")
    guard content.categoryIdentifier == category else { return false }
    if let key = content.userInfo["key"] as? String { cancelRepeats(for: key) }
    if response.actionIdentifier == joinAction || response.actionIdentifier == UNNotificationDefaultActionIdentifier,
      let target = content.userInfo["target"] as? String, let url = URL(string: target)
    {
      log.info("joining \(url.absoluteString, privacy: .public)")
      UIApplication.shared.open(url)
    }
    return true
  }

  @available(iOS 26.0, *)
  private static func configuration(
    for call: LessonCall,
    labels: CallPayload
  ) -> AlarmManager.AlarmConfiguration<LessonCallMetadata> {
    let brand = Color(red: 23 / 255, green: 107 / 255, blue: 69 / 255)
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: call.alertTitle(incoming: labels.incoming)),
      stopButton: AlarmButton(
        text: LocalizedStringResource(stringLiteral: labels.decline),
        textColor: .white,
        systemImageName: "xmark"
      ),
      secondaryButton: AlarmButton(
        text: LocalizedStringResource(stringLiteral: labels.answer),
        textColor: .white,
        systemImageName: "video.fill"
      ),
      secondaryButtonBehavior: .custom
    )
    return .alarm(
      schedule: .fixed(call.startDate),
      attributes: AlarmAttributes(
        presentation: AlarmPresentation(alert: alert),
        metadata: LessonCallMetadata(),
        tintColor: brand
      ),
      secondaryIntent: JoinLessonIntent(target: joinTarget(for: call.meetingUrl))
    )
  }

  /// Where Join goes, following `LessonLinkRouter.kt`: only HTTPS without
  /// user info leaves the app, an LMS link reopens KIU on that page, and a
  /// missing or unsafe link just opens KIU.
  static func joinTarget(for meetingUrl: String?) -> String {
    let openApp = "kiu://open?homeWidget=1"
    guard let raw = meetingUrl, let url = URL(string: raw),
      url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
      url.user == nil, url.password == nil
    else { return openApp }
    guard host == trustedHost else { return raw }
    var components = URLComponents()
    components.scheme = "kiu"
    components.host = "open"
    components.queryItems = [
      URLQueryItem(name: "homeWidget", value: "1"),
      URLQueryItem(name: "target", value: raw),
    ]
    return components.url?.absoluteString ?? openApp
  }
}

/// AlarmKit requires a metadata type; KIU carries nothing extra in it.
@available(iOS 26.0, *)
struct LessonCallMetadata: AlarmMetadata {}

/// Join on the alarm. Runs in the app's process and opens the link: a meeting
/// app or Safari for an external link, KIU itself for `kiu://`.
@available(iOS 26.0, *)
struct JoinLessonIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Join the lesson"
  static var openAppWhenRun = true

  @Parameter(title: "Link")
  var target: String

  init() { target = "kiu://open?homeWidget=1" }
  init(target: String) { self.target = target }

  @MainActor
  func perform() async throws -> some IntentResult {
    if let url = URL(string: target) {
      await UIApplication.shared.open(url)
    }
    return .result()
  }
}

/// One entry of the `calls` array built by `buildLessonCallPayload`.
struct LessonCall: Decodable {
  let key: String
  let title: String
  let displayStart: String
  /// Epoch milliseconds.
  let start: Double
  let meetingUrl: String?

  var startDate: Date { Date(timeIntervalSince1970: start / 1000) }

  func alertTitle(incoming: String) -> String {
    displayStart.isEmpty ? "\(incoming): \(title)" : "\(incoming): \(title)\n\(displayStart)"
  }
}

/// The call schedule plus its pre-localized labels, read tolerantly from the
/// App Group: anything missing or malformed means "no calls", never a crash.
struct CallPayload {
  var calls: [LessonCall] = []
  var incoming = "Lesson starting"
  var answer = "Join"
  var decline = "Dismiss"
  /// How long a call rings (the app's "Ring duration"), clamped like Dart's.
  var ringSeconds: TimeInterval = 60

  static func load() -> CallPayload {
    var payload = CallPayload()
    guard let defaults = UserDefaults(suiteName: LessonCalls.appGroup) else { return payload }
    func text(_ key: String) -> String? {
      guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
      return value
    }
    if let json = text("calls")?.data(using: .utf8),
      let calls = try? JSONDecoder().decode([LessonCall].self, from: json)
    {
      payload.calls = calls.sorted { $0.start < $1.start }
    }
    payload.incoming = text("callIncomingLabel") ?? payload.incoming
    payload.answer = text("callAnswerLabel") ?? payload.answer
    payload.decline = text("callDeclineLabel") ?? payload.decline
    if let seconds = text("callRingSeconds").flatMap(Double.init) {
      payload.ringSeconds = min(300, max(10, seconds))
    }
    return payload
  }
}
