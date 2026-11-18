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
  let preferences = MemoryPreferences(defaults: defaults)
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
