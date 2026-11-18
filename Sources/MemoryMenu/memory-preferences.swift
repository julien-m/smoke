// Stores status-item presentation and app footprint thresholds for this user.
import Combine
import Foundation

enum AppLanguage: String, CaseIterable {
  case system
  case english = "en"
  case french = "fr"

  var locale: Locale {
    self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
  }

  func localized(_ key: String, in bundle: Bundle = .main) -> String {
    if self != .system, let url = bundle.url(forResource: rawValue, withExtension: "lproj"),
      let translation = Bundle(url: url)
    {
      return translation.localizedString(forKey: key, value: nil, table: nil)
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
  }
}

struct SystemMemoryThresholds: Equatable {
  static let percentMaximum = 100
  static let initial = Self(validWarning: 80, validCritical: 90)

  let warning: Int
  let critical: Int

  init?(warning: Int, critical: Int) {
    guard warning >= 1, warning < critical, critical <= Self.percentMaximum else { return nil }
    self.init(validWarning: warning, validCritical: critical)
  }

  private init(validWarning: Int, validCritical: Int) {
    self.warning = validWarning
    self.critical = validCritical
  }

  func level(usedPercent: Int) -> MemoryLevel {
    if usedPercent >= critical { return .critical }
    if usedPercent >= warning { return .warning }
    return .normal
  }
}

enum MemoryDisplay: String, CaseIterable {
  case icon, used, available
}

enum MemoryLevel: Int, Comparable {
  case normal, warning, critical

  static func < (left: Self, right: Self) -> Bool {
    left.rawValue < right.rawValue
  }
}

struct AppMemoryThresholds: Equatable {
  static let minimumGB = 1
  static let maximumGB = 256
  static let initial = Self(warningGB: 2, criticalGB: 4)
  private static let bytesPerGB: UInt64 = 1_000_000_000

  let warningGB: Int
  let criticalGB: Int

  func level(bytes: UInt64?) -> MemoryLevel {
    guard let bytes else { return .normal }
    if bytes >= UInt64(criticalGB) * Self.bytesPerGB { return .critical }
    if bytes >= UInt64(warningGB) * Self.bytesPerGB { return .warning }
    return .normal
  }
}

@MainActor
final class MemoryPreferences: ObservableObject {
  private enum Key {
    static let display = "status-display"
    static let language = "app-language"
    static let systemWarning = "system-warning-percent"
    static let systemCritical = "system-critical-percent"
    static let warningGB = "app-warning-gb"
    static let criticalGB = "app-critical-gb"
  }

  @Published var display: MemoryDisplay {
    didSet { defaults.set(display.rawValue, forKey: Key.display) }
  }

  @Published var language: AppLanguage {
    didSet { defaults.set(language.rawValue, forKey: Key.language) }
  }

  @Published private(set) var systemThresholds: SystemMemoryThresholds
  @Published private(set) var thresholds: AppMemoryThresholds
  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
    display = defaults.string(forKey: Key.display).flatMap(MemoryDisplay.init(rawValue:)) ?? .icon
    language = defaults.string(forKey: Key.language).flatMap(AppLanguage.init(rawValue:)) ?? .system
    systemThresholds =
      SystemMemoryThresholds(
        warning: defaults.integer(forKey: Key.systemWarning),
        critical: defaults.integer(forKey: Key.systemCritical)
      ) ?? .initial
    let warning = defaults.object(forKey: Key.warningGB) as? Int
    let critical = defaults.object(forKey: Key.criticalGB) as? Int
    if let warning, let critical,
      warning >= AppMemoryThresholds.minimumGB, critical <= AppMemoryThresholds.maximumGB,
      warning < critical
    {
      thresholds = AppMemoryThresholds(warningGB: warning, criticalGB: critical)
    } else {
      thresholds = .initial
    }
  }

  func setWarning(_ value: Int) {
    guard (AppMemoryThresholds.minimumGB..<thresholds.criticalGB).contains(value) else { return }
    save(AppMemoryThresholds(warningGB: value, criticalGB: thresholds.criticalGB))
  }

  func setCritical(_ value: Int) {
    guard value > thresholds.warningGB, value <= AppMemoryThresholds.maximumGB else { return }
    save(AppMemoryThresholds(warningGB: thresholds.warningGB, criticalGB: value))
  }

  func setSystemWarning(_ value: Int) {
    setSystemThresholds(warning: value, critical: systemThresholds.critical)
  }

  func setSystemCritical(_ value: Int) {
    setSystemThresholds(warning: systemThresholds.warning, critical: value)
  }

  private func setSystemThresholds(warning: Int, critical: Int) {
    guard let value = SystemMemoryThresholds(warning: warning, critical: critical) else { return }
    systemThresholds = value
    defaults.set(value.warning, forKey: Key.systemWarning)
    defaults.set(value.critical, forKey: Key.systemCritical)
  }

  private func save(_ value: AppMemoryThresholds) {
    thresholds = value
    defaults.set(value.warningGB, forKey: Key.warningGB)
    defaults.set(value.criticalGB, forKey: Key.criticalGB)
  }
}
