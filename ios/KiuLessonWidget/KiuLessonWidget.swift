import SwiftUI
import WidgetKit

/// Must match `iosAppGroupId` in `lib/core/platform.dart` and both
/// `.entitlements` files.
private let appGroup = "group.com.mashkhurbek.kiu"
/// The only host whose links may reopen KIU; mirrors `trustedHost` in Dart.
private let trustedHost = "uz.do-kazankiu.ru"

// MARK: - Data

/// One row of the `lessons` JSON written by `HomeLessonWidgetGateway.publish`.
struct WidgetLesson: Decodable, Identifiable {
  let key: String
  let title: String
  /// Epoch milliseconds.
  let start: Double
  let displayStart: String
  let meetingUrl: String?

  var id: String { "\(key)|\(start)" }
  var startDate: Date { Date(timeIntervalSince1970: start / 1000) }
}

/// Everything the widget renders, read once per timeline from the shared
/// `UserDefaults` suite. Every read is tolerant: a missing or malformed value
/// falls back to an empty widget rather than a crash, the same contract the
/// Dart `SettingsRepository` keeps.
struct LessonSnapshot {
  var lessons: [WidgetLesson] = []
  var subtitle = "Scheduled online lessons"
  var emptyLabel = "No scheduled lessons"
  var lastSync = ""
  var status = ""
  var syncing = false
  var syncLabel = "Sync"
  var dark: Bool? = nil
  var todayLabel = "Today"
  var tomorrowLabel = "Tomorrow"
  var othersLabel = "Others"
  var timeZone = TimeZone(identifier: "Asia/Tashkent") ?? .current

  static func load() -> LessonSnapshot {
    var snapshot = LessonSnapshot()
    guard let defaults = UserDefaults(suiteName: appGroup) else { return snapshot }
    func text(_ key: String) -> String? {
      guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
      return value
    }
    if let json = text("lessons")?.data(using: .utf8),
      let lessons = try? JSONDecoder().decode([WidgetLesson].self, from: json)
    {
      snapshot.lessons = lessons.sorted { $0.start < $1.start }
    }
    snapshot.subtitle = text("widgetSubtitle") ?? snapshot.subtitle
    snapshot.emptyLabel = text("emptyLabel") ?? snapshot.emptyLabel
    snapshot.lastSync = text("widgetLastSync") ?? ""
    snapshot.status = text("widgetStatus") ?? ""
    snapshot.syncing = text("widgetIsSyncing") == "true"
    snapshot.syncLabel = text("syncLabel") ?? snapshot.syncLabel
    snapshot.dark = text("widgetDark").map { $0 == "true" }
    snapshot.todayLabel = text("groupTodayLabel") ?? snapshot.todayLabel
    snapshot.tomorrowLabel = text("groupTomorrowLabel") ?? snapshot.tomorrowLabel
    snapshot.othersLabel = text("groupOthersLabel") ?? snapshot.othersLabel
    if let zone = text("widgetTimeZone").flatMap(TimeZone.init(identifier:)) {
      snapshot.timeZone = zone
    }
    return snapshot
  }
}

enum LessonGroup: Int { case today, tomorrow, others }

extension LessonSnapshot {
  func group(of lesson: WidgetLesson, at now: Date) -> LessonGroup {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let days =
      calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: now),
        to: calendar.startOfDay(for: lesson.startDate)
      ).day ?? 2
    switch days {
    case ...0: return .today
    case 1: return .tomorrow
    default: return .others
    }
  }

  func label(for group: LessonGroup) -> String {
    switch group {
    case .today: return todayLabel
    case .tomorrow: return tomorrowLabel
    case .others: return othersLabel
    }
  }
}

// MARK: - Timeline

struct LessonEntry: TimelineEntry {
  let date: Date
  let snapshot: LessonSnapshot
}

struct LessonProvider: TimelineProvider {
  func placeholder(in context: Context) -> LessonEntry {
    LessonEntry(date: Date(), snapshot: LessonSnapshot())
  }

  func getSnapshot(in context: Context, completion: @escaping (LessonEntry) -> Void) {
    completion(LessonEntry(date: Date(), snapshot: .load()))
  }

  /// One entry now, one at each upcoming lesson start (so a row turns green
  /// without a sync) and one at the next two midnights (so "Tomorrow" becomes
  /// "Today"). Capped like the Android widget's scheduled updates: the next
  /// publish rebuilds the timeline long before the tail matters.
  func getTimeline(in context: Context, completion: @escaping (Timeline<LessonEntry>) -> Void) {
    let snapshot = LessonSnapshot.load()
    let now = Date()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = snapshot.timeZone
    let today = calendar.startOfDay(for: now)
    let midnights = (1...2).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    let starts = snapshot.lessons.map(\.startDate).filter { $0 > now }.prefix(16)
    let dates = Set([now] + midnights + starts).sorted()
    let entries = dates.map { LessonEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

// MARK: - Palette

/// Mirrors `WidgetTheme.kt` and `lib/core/theme.dart`: the three copies are
/// duplicated on purpose (see CLAUDE.md) and must change together.
private enum Palette {
  static func brand(_ dark: Bool) -> Color { dark ? rgb(111, 211, 160) : rgb(23, 107, 69) }
  static func strong(_ dark: Bool) -> Color { dark ? rgb(245, 245, 245) : rgb(15, 15, 15) }
  static func muted(_ dark: Bool) -> Color { dark ? rgb(168, 168, 168) : rgb(115, 115, 115) }
  static func rule(_ dark: Bool) -> Color { dark ? rgb(38, 38, 38) : rgb(219, 219, 219) }
  /// Frosted backdrop for full-color mode: a faint brand tint, so the
  /// translucent panels on top read as glass rather than grey boxes.
  static func backdrop(_ dark: Bool) -> LinearGradient {
    LinearGradient(
      colors: dark
        ? [rgb(34, 44, 40), rgb(14, 18, 16)]
        : [rgb(250, 252, 251), rgb(222, 236, 229)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  static func panel(_ dark: Bool) -> Color { dark ? Color.white.opacity(0.07) : Color.white.opacity(0.62) }

  /// The bright top edge that sells a pane as glass.
  static func edge(_ dark: Bool) -> LinearGradient {
    LinearGradient(
      colors: [Color.white.opacity(dark ? 0.28 : 0.95), Color.white.opacity(dark ? 0.04 : 0.25)],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  static func title(_ dark: Bool, started: Bool, today: Bool) -> Color {
    if started { return brand(dark) }
    if today { return dark ? rgb(227, 184, 95) : rgb(122, 85, 0) }
    return strong(dark)
  }

  static func time(_ dark: Bool, started: Bool, today: Bool) -> Color {
    if started { return brand(dark) }
    if today { return dark ? rgb(212, 170, 82) : rgb(138, 101, 0) }
    return muted(dark)
  }

  /// Status colors for icons on Liquid Glass: the theme palette's amber and
  /// green are tuned for a white or black card and go muddy on glass.
  static let glassAmber = rgb(255, 196, 64)
  static let glassGreen = rgb(72, 222, 140)

  private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r / 255, green: g / 255, blue: b / 255)
  }
}

// MARK: - Links

/// Where a started lesson's row goes, following `LessonLinkRouter.kt`: only a
/// valid HTTPS link without user info is followed, an LMS link reopens KIU on
/// that page, and anything else goes to the system (Meet, Zoom, Safari).
func joinURL(for lesson: WidgetLesson) -> URL? {
  guard let raw = lesson.meetingUrl, let url = URL(string: raw),
    url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
    url.user == nil, url.password == nil
  else { return nil }
  guard host == trustedHost else { return url }
  var components = URLComponents()
  components.scheme = "kiu"
  components.host = "open"
  components.queryItems = [
    URLQueryItem(name: "homeWidget", value: "1"),
    URLQueryItem(name: "target", value: raw),
  ]
  return components.url
}

/// Reopens KIU; the app's resume sync is the widget's Sync.
private let openAppURL = URL(string: "kiu://widget-sync?homeWidget=1")!

// MARK: - Views

struct LessonWidgetView: View {
  let entry: LessonEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var systemScheme
  /// `.accented` is the Home Screen's Clear or Tinted style: iOS draws the
  /// Liquid Glass itself, removes our background and tints what is marked
  /// accentable, so the view must not paint its own surfaces or colors.
  @Environment(\.widgetRenderingMode) private var renderingMode
  private var systemGlass: Bool { renderingMode != .fullColor }

  private var snapshot: LessonSnapshot { entry.snapshot }
  /// Follows the in-app Appearance setting, like the Android widget.
  private var dark: Bool { snapshot.dark ?? (systemScheme == .dark) }

  private var rowLimit: Int {
    switch family {
    case .systemSmall: return 2
    case .systemMedium: return 4
    default: return 7
    }
  }

  var body: some View {
    Group {
      if family == .accessoryRectangular {
        accessory
      } else {
        board
      }
    }
    .widgetURL(openAppURL)
    .environment(\.colorScheme, dark ? .dark : .light)
    .containerBackground(for: .widget) { Palette.backdrop(dark) }
  }

  private var board: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      if snapshot.lessons.isEmpty {
        Spacer(minLength: 0)
        Text(snapshot.emptyLabel)
          .font(.subheadline)
          .foregroundStyle(Palette.muted(dark))
          .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
      } else {
        rows
        Spacer(minLength: 0)
      }
    }
  }

  /// "Last sync: 12:28" trimmed to its time, since the refresh icon beside it
  /// already says what the time is; a status such as "Open KIU and sign in"
  /// wins, because it is the thing to act on.
  private var syncCaption: String {
    if !snapshot.status.isEmpty { return snapshot.status }
    guard let separator = snapshot.lastSync.range(of: ": ") else { return snapshot.lastSync }
    return String(snapshot.lastSync[separator.upperBound...])
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 0) {
        Text("KIU")
          .font(.headline.weight(.bold))
          .foregroundStyle(Palette.brand(dark))
          .widgetAccentable()
        // Only the large size has a spare line for it.
        if family == .systemLarge {
          Text(snapshot.subtitle)
            .font(.caption2)
            .foregroundStyle(Palette.muted(dark))
            .lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if family != .systemSmall, let next = snapshot.lessons.first(where: { $0.startDate > entry.date }) {
        // Counts down live on its own -- WidgetKit re-renders relative dates
        // without a timeline entry.
        HStack(spacing: 3) {
          glassColoredIcon(
            "hourglass",
            color: systemGlass ? Palette.glassAmber : Palette.title(dark, started: false, today: true),
            font: .caption2.weight(.semibold)
          )
          Text(next.startDate, style: .relative)
            .foregroundStyle(Palette.strong(dark))
            .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
      }
      if family != .systemSmall {
        // Last sync (or the sync status while it matters) sits next to the
        // button that refreshes it, so the two read as one control.
        Text(syncCaption)
          .font(.caption2)
          .foregroundStyle(Palette.muted(dark))
          .lineLimit(1)
      }
      Link(destination: openAppURL) {
        Image(systemName: snapshot.syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.strong(dark))
          .padding(6)
          .background {
            if !systemGlass {
              Circle().fill(Palette.panel(dark))
                .overlay(Circle().strokeBorder(Palette.edge(dark), lineWidth: 0.8))
            }
          }
          .accessibilityLabel(snapshot.syncLabel)
      }
    }
  }

  private var rows: some View {
    let shown = Array(snapshot.lessons.prefix(rowLimit))
    return VStack(alignment: .leading, spacing: 3) {
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, lesson in
        let group = snapshot.group(of: lesson, at: entry.date)
        if family != .systemSmall,
          index == 0 || snapshot.group(of: shown[index - 1], at: entry.date) != group
        {
          Text(snapshot.label(for: group).uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Palette.muted(dark))
            .padding(.top, index == 0 ? 0 : 2)
        }
        row(lesson, group: group)
      }
    }
  }

  @ViewBuilder
  private func row(_ lesson: WidgetLesson, group: LessonGroup) -> some View {
    let started = lesson.startDate <= entry.date
    let today = group == .today
    let content = HStack(spacing: 6) {
      // The one element that keeps its color in the Clear and Tinted styles,
      // where iOS flattens text and shapes to a single tint: green "live" for
      // a started lesson, amber clock for later today, grey calendar after.
      glassColoredIcon(
        started ? "dot.radiowaves.left.and.right" : today ? "clock.fill" : "calendar",
        color: statusColor(started: started, today: today),
        font: .system(size: systemGlass ? 12 : 10, weight: .semibold)
      )
        .frame(width: 14)
      Text(lesson.title)
        .font(.caption.weight(started || today ? .semibold : .regular))
        .foregroundStyle(Palette.title(dark, started: started, today: today))
        .lineLimit(1)
      Spacer(minLength: 4)
      // Today and Tomorrow rows sit under a heading that already names the
      // day, so the time alone is enough and leaves room for the title.
      Text(family == .systemSmall || group != .others ? String(lesson.displayStart.prefix(5)) : lesson.displayStart)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Palette.time(dark, started: started, today: today))
        .lineLimit(1)
    }
    .frame(height: 17)
    .padding(.horizontal, 6)
    .padding(.vertical, 1.5)
    // In the glass styles brightness is the only hierarchy left, so later
    // lessons step back behind today's.
    .opacity(systemGlass && !(started || today) ? 0.65 : 1)
    let pane = glassPane(radius: 9) { content }
    if started, let url = joinURL(for: lesson) {
      Link(destination: url) { pane }
    } else {
      pane
    }
  }

  private func statusColor(started: Bool, today: Bool) -> Color {
    if systemGlass {
      if started { return Palette.glassGreen }
      if today { return Palette.glassAmber }
      return .white.opacity(0.7)
    }
    return started || today ? Palette.title(dark, started: started, today: today) : Palette.muted(dark)
  }

  /// A frosted pane in full color; nothing in the system glass styles, where
  /// iOS already provides the glass.
  @ViewBuilder
  private func glassPane<Content: View>(radius: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
    if systemGlass {
      content()
    } else {
      content()
        .background(
          RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.panel(dark))
            .overlay(
              RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.edge(dark), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(dark ? 0.25 : 0.06), radius: 3, y: 1)
        )
    }
  }

  /// Lock Screen: the next lesson only, in the system's monochrome style.
  private var accessory: some View {
    let next = snapshot.lessons.first { $0.startDate > entry.date.addingTimeInterval(-3600) }
    return VStack(alignment: .leading, spacing: 1) {
      Text("KIU").font(.caption2.weight(.bold)).widgetAccentable()
      if let next {
        Text(next.title).font(.headline).lineLimit(1)
        Text(next.displayStart).font(.caption)
      } else {
        Text(snapshot.emptyLabel).font(.caption).lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Widget

struct KiuLessonWidget: Widget {
  /// Must match `iosLessonWidgetKind` in `lib/core/platform.dart`.
  let kind = "KiuLessonWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: LessonProvider()) { entry in
      LessonWidgetView(entry: entry)
    }
    .configurationDisplayName("KIU")
    .description("Scheduled online lessons")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
  }
}

@main
struct KiuWidgetBundle: WidgetBundle {
  var body: some Widget {
    KiuLessonWidget()
  }
}

/// A status icon that keeps its color in the Clear and Tinted styles (iOS
/// 18+), where iOS otherwise flattens everything to one tint -- the only way
/// to keep green and amber on Liquid Glass.
@ViewBuilder
func glassColoredIcon(_ name: String, color: Color, font: Font) -> some View {
  if #available(iOS 18.0, *) {
    Image(systemName: name)
      .widgetAccentedRenderingMode(.fullColor)
      .font(font)
      .foregroundStyle(color)
  } else {
    Image(systemName: name)
      .font(font)
      .foregroundStyle(color)
  }
}
