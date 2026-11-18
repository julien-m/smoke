// Edits the same physical memory thresholds in used or available percentages.
import SwiftUI

struct SystemThresholdSettings: View {
  @ObservedObject var preferences: MemoryPreferences

  private var showsAvailable: Bool { preferences.display == .available }

  var body: some View {
    let thresholds = preferences.systemThresholds
    VStack(alignment: .leading, spacing: 8) {
      Text("settings.system-thresholds").font(.callout.weight(.semibold))
      Stepper(
        value: binding(used: thresholds.warning, set: { preferences.setSystemWarning($0) }),
        in: displayedRange(1...(thresholds.critical - 1))
      ) {
        thresholdLabel(critical: false, value: displayed(thresholds.warning))
      }
      Stepper(
        value: binding(used: thresholds.critical, set: { preferences.setSystemCritical($0) }),
        in: displayedRange((thresholds.warning + 1)...SystemMemoryThresholds.percentMaximum)
      ) {
        thresholdLabel(critical: true, value: displayed(thresholds.critical))
      }
      if preferences.display == .icon {
        Text("settings.pressure-note").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func binding(used: Int, set: @escaping (Int) -> Void) -> Binding<Int> {
    Binding(get: { displayed(used) }, set: { set(displayed($0)) })
  }

  private func displayed(_ value: Int) -> Int {
    showsAvailable ? SystemMemoryThresholds.percentMaximum - value : value
  }

  private func displayedRange(_ range: ClosedRange<Int>) -> ClosedRange<Int> {
    showsAvailable ? displayed(range.upperBound)...displayed(range.lowerBound) : range
  }

  private func thresholdLabel(critical: Bool, value: Int) -> some View {
    let ratio = Double(value) / Double(SystemMemoryThresholds.percentMaximum)
    let percent = ratio.formatted(
      .percent.precision(.fractionLength(0)).locale(preferences.language.locale))
    return Label {
      if showsAvailable {
        if critical {
          Text("settings.system-critical-available \(percent)")
        } else {
          Text("settings.system-warning-available \(percent)")
        }
      } else {
        if critical {
          Text("settings.system-critical-used \(percent)")
        } else {
          Text("settings.system-warning-used \(percent)")
        }
      }
    } icon: {
      Image(systemName: "circle.fill").foregroundStyle(critical ? Color.red : .orange)
    }
  }
}
