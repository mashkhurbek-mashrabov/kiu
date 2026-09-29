import Flutter
import UIKit
import UserNotifications
import workmanager_apple

/// Must match `backgroundTaskUniqueName` in `lib/core/constants.dart` and the
/// `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
private let scheduleSyncTaskIdentifier = "kiu.periodicScheduleSync"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Reminders scheduled by flutter_local_notifications only show while the
    // app is open if this delegate is set, and taps are only delivered to Dart
    // through it.
    UNUserNotificationCenter.current().delegate = self

    // The background sync runs in a headless engine, which needs its own
    // plugins -- WebView cookies, preferences and notifications among them.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    // BGTaskScheduler requires every launch handler to be registered before
    // launch finishes; the Dart side only submits the request.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: scheduleSyncTaskIdentifier,
      earliestBeginInSeconds: NSNumber(value: 15 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KiuPlatformPlugin") {
      KiuPlatformPlugin.register(with: registrar)
    }
    engineBridge.pluginRegistry.registrar(forPlugin: "KiuGlass")?
      .register(GlassBackgroundFactory(), withId: "kiu/glass")
  }
}

/// The iOS side of `com.mashkhurbek.kiu/platform`.
///
/// Only the app version exists here. Everything else the Android channel
/// carries -- battery, overlay and full-screen permissions, the APK installer,
/// the system sound picker -- has no iOS counterpart, and the Dart side never
/// calls it on iOS. An unknown method answers `notImplemented`, which Dart
/// surfaces as `MissingPluginException` and already tolerates.
final class KiuPlatformPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.mashkhurbek.kiu/platform",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(KiuPlatformPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAppVersion":
      let info = Bundle.main.infoDictionary
      let name = info?["CFBundleShortVersionString"] as? String
      let build = (info?["CFBundleVersion"] as? String).flatMap { Int($0) }
      guard let name, let build else {
        result(FlutterError(code: "invalid_app_version", message: nil, details: nil))
        return
      }
      // No ABI split on iOS: one binary serves every device.
      result(["versionName": name, "versionCode": build, "abi": 0])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// A system glass surface for Flutter chrome to sit on (`kiu/glass`).
///
/// Flutter paints its own widgets, so it cannot produce iOS 26's Liquid Glass.
/// This view is the real `UIGlassEffect`, placed as a platform view *behind*
/// the Flutter buttons: because the WebView is also a native view, the glass
/// samples and refracts the actual page scrolling under it. Earlier iOS gets
/// the system chrome blur instead.
///
/// Creation params: `dark` (Bool) pins the glass to the app's own appearance
/// setting rather than the system's, the same way the rest of KIU does.
final class GlassBackgroundFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let dark = (args as? [String: Any])?["dark"] as? Bool ?? false
    return GlassBackground(frame: frame, dark: dark)
  }
}

private final class GlassBackground: NSObject, FlutterPlatformView {
  private let effectView: CapsuleEffectView

  init(frame: CGRect, dark: Bool) {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      effect = UIGlassEffect(style: .regular)
    } else {
      effect = UIBlurEffect(style: .systemChromeMaterial)
    }
    effectView = CapsuleEffectView(effect: effect)
    effectView.frame = frame
    effectView.overrideUserInterfaceStyle = dark ? .dark : .light
    // Touches belong to the Flutter buttons drawn on top.
    effectView.isUserInteractionEnabled = false
    super.init()
  }

  func view() -> UIView { effectView }
}

/// Keeps the pill shape at whatever height Flutter lays the view out at.
private final class CapsuleEffectView: UIVisualEffectView {
  override func layoutSubviews() {
    super.layoutSubviews()
    if #available(iOS 26.0, *) {
      cornerConfiguration = .capsule()
    } else {
      layer.cornerCurve = .continuous
      layer.cornerRadius = bounds.height / 2
      clipsToBounds = true
    }
  }
}
