import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    let defaultSize = NSSize(width: 1100, height: 750)
    self.minSize = NSSize(width: 800, height: 600)

    var windowFrame = self.frame
    windowFrame.size = defaultSize
    self.setFrame(windowFrame, display: true)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    KiuPlatformPlugin.register(with: flutterViewController.registrar(forPlugin: "KiuPlatformPlugin"))

    super.awakeFromNib()
  }
}

final class KiuPlatformPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.mashkhurbek.kiu/platform",
      binaryMessenger: registrar.messenger
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
      result(["versionName": name, "versionCode": build, "abi": 0])
    case "lessonCallsAvailable":
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
