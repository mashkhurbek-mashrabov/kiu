import AVFoundation
import AudioToolbox
import SwiftUI
import UIKit

/// The in-app incoming-call screen: the iOS twin of `LessonCallActivity`.
///
/// iOS cannot put an app on screen by itself, so this only appears when a call
/// comes due while KIU is already open; otherwise the ringing notification or
/// the AlarmKit alert is the call. Like the Android screen it never scrolls:
/// identity in the middle, Decline and Join pinned to the bottom.
@MainActor
final class CallScreen {
  static let shared = CallScreen()

  private weak var controller: UIViewController?
  private var player: AVAudioPlayer?
  private var vibration: Timer?
  private var timeout: DispatchWorkItem?
  private(set) var ringingKey: String?

  /// Rings for [ringSeconds] unless answered or declined first.
  func present(
    key: String,
    title: String,
    time: String,
    incoming: String,
    answer: String,
    decline: String,
    target: String,
    ringSeconds: TimeInterval
  ) {
    guard ringingKey == nil, let host = Self.topController() else { return }
    ringingKey = key
    let view = CallView(
      title: title,
      time: time,
      incoming: incoming,
      answer: answer,
      decline: decline,
      onAnswer: { [weak self] in
        self?.finish()
        if let url = URL(string: target) { UIApplication.shared.open(url) }
      },
      onDecline: { [weak self] in self?.finish() }
    )
    let controller = UIHostingController(rootView: view)
    controller.modalPresentationStyle = .fullScreen
    controller.modalTransitionStyle = .crossDissolve
    host.present(controller, animated: true)
    self.controller = controller
    startRinging(for: ringSeconds)
  }

  func finish() {
    if let key = ringingKey { LessonCalls.cancelRepeats(for: key) }
    ringingKey = nil
    player?.stop()
    player = nil
    vibration?.invalidate()
    vibration = nil
    timeout?.cancel()
    timeout = nil
    controller?.dismiss(animated: true)
    controller = nil
  }

  private func startRinging(for seconds: TimeInterval) {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
    try? session.setActive(true)
    if let url = Bundle.main.url(forResource: "kiu_ring", withExtension: "caf") {
      player = try? AVAudioPlayer(contentsOf: url)
      player?.numberOfLoops = -1
      player?.play()
    }
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    vibration = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    let stop = DispatchWorkItem { [weak self] in self?.finish() }
    timeout = stop
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: stop)
  }

  private static func topController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

private struct CallView: View {
  let title: String
  let time: String
  let incoming: String
  let answer: String
  let decline: String
  let onAnswer: () -> Void
  let onDecline: () -> Void

  @State private var pulse = false

  private let brand = Color(red: 23 / 255, green: 107 / 255, blue: 69 / 255)

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [brand, Color(red: 8 / 255, green: 40 / 255, blue: 27 / 255), .black],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      VStack(spacing: 0) {
        Text("KIU")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(.white.opacity(0.85))
          .padding(.horizontal, 14)
          .padding(.vertical, 6)
          .background(Capsule().fill(.white.opacity(0.14)))
          .padding(.top, 24)

        Spacer()

        ZStack {
          ForEach(0..<2) { ring in
            Circle()
              .stroke(.white.opacity(0.25), lineWidth: 2)
              .frame(width: 132, height: 132)
              .scaleEffect(pulse ? 1.6 + CGFloat(ring) * 0.3 : 1)
              .opacity(pulse ? 0 : 0.8)
          }
          Circle()
            .fill(.white.opacity(0.12))
            .frame(width: 132, height: 132)
          Image(systemName: "video.fill")
            .font(.system(size: 48, weight: .semibold))
            .foregroundStyle(.white)
        }
        .onAppear {
          withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulse = true
          }
        }

        Text(incoming)
          .font(.headline)
          .foregroundStyle(.white.opacity(0.75))
          .padding(.top, 36)
        Text(title)
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.white)
          .multilineTextAlignment(.center)
          .lineLimit(3)
          .minimumScaleFactor(0.6)
          .padding(.horizontal, 28)
          .padding(.top, 8)
        if !time.isEmpty {
          Text(time)
            .font(.title3.monospacedDigit())
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 10)
        }

        Spacer()

        HStack(spacing: 72) {
          callButton(decline, icon: "phone.down.fill", color: .red, action: onDecline)
          callButton(answer, icon: "video.fill", color: .green, action: onAnswer)
        }
        .padding(.bottom, 48)
      }
    }
  }

  private func callButton(
    _ label: String,
    icon: String,
    color: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 30, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 78, height: 78)
          .modifier(GlassDisc(color: color))
        Text(label)
          .font(.callout.weight(.medium))
          .foregroundStyle(.white)
      }
    }
    .buttonStyle(.plain)
  }
}

/// Liquid Glass tinted discs on iOS 26+, solid discs before.
private struct GlassDisc: ViewModifier {
  let color: Color

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(.regular.tint(color).interactive(), in: Circle())
    } else {
      content.background(Circle().fill(color))
    }
  }
}
