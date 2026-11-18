// Verifies threshold boundaries, persisted settings, and the private ABI gate.
import Foundation
import Testing

@testable import MemoryMenu

@Test func availablePercentageUsesTheSameAlertAsUsedPercentage() {
  let reading = SystemMemory(usedRatio: 0.86)
  #expect(reading.usedPercent == 86)
  #expect(reading.availablePercent == 14)
  let defaults = SystemMemoryThresholds.initial
  #expect(defaults.level(usedPercent: reading.usedPercent) == .warning)
  #expect(defaults.level(usedPercent: defaults.warning - 1) == .normal)
  #expect(defaults.level(usedPercent: defaults.critical) == .critical)
}

@Test @MainActor func languageAndThresholdPreferencesSurviveReload() throws {
  let domain = "SmokeTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: domain))
  defer { defaults.removePersistentDomain(forName: domain) }
  // Values stored under the legacy keys must remain integers.
  defaults.set("7", forKey: "app-warning-gb")
  defaults.set("9", forKey: "app-critical-gb")
  let preferences = MemoryPreferences(defaults: defaults)
  #expect(preferences.thresholds == .initial)
  #expect(preferences.language == .system)
  preferences.language = .french
  let defaultsThresholds = preferences.systemThresholds
  preferences.setSystemWarning(defaultsThresholds.warning - 5)
  preferences.setSystemCritical(defaultsThresholds.critical - 5)
  preferences.setSystemWarning(defaultsThresholds.critical)
  let reloaded = MemoryPreferences(defaults: defaults)
  #expect(reloaded.language == .french)
  #expect(reloaded.systemThresholds.warning == defaultsThresholds.warning - 5)
  #expect(reloaded.systemThresholds.critical == defaultsThresholds.critical - 5)
}

@Test func unsupportedSystemDoesNotReadPrivateCoalitionMembership() async {
  let runningOS = ProcessInfo.processInfo.operatingSystemVersion
  let unsupported = OperatingSystemVersion(
    majorVersion: runningOS.majorVersion + 1,
    minorVersion: runningOS.minorVersion,
    patchVersion: runningOS.patchVersion
  )
  let pid = ProcessInfo.processInfo.processIdentifier
  let sampler = MemorySampler(version: unsupported)
  let sample = await sampler.sample(applications: [pid], expanded: pid)
  #expect(sample.applications.isEmpty)
  #expect(sample.processes == nil)
}

@Test func appOrderSwitchesBetweenMemoryAndLocalizedNames() {
  let noReading = AppSortKey(name: "A", bytes: nil, pid: 1)
  let highest = AppSortKey(name: "Z", bytes: 300, pid: 2)
  let equalReadingLowerPID = AppSortKey(name: "A", bytes: 200, pid: 3)
  let equalReadingHigherPID = AppSortKey(name: "A", bytes: 200, pid: 4)
  let rows = [equalReadingHigherPID, highest, noReading, equalReadingLowerPID]
  let memory = AppSortOrder.memory
  #expect(
    rows.sorted(by: memory.precedes).map(\.pid)
      == [highest, equalReadingLowerPID, equalReadingHigherPID, noReading].map(\.pid))
  #expect(
    rows.sorted(by: memory.alternate.precedes).map(\.pid)
      == [noReading, equalReadingLowerPID, equalReadingHigherPID, highest].map(\.pid))
  #expect(memory.alternate.alternate == .memory)
}
