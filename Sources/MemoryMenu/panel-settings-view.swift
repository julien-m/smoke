// Presents the language, memory thresholds, and launch-at-login preferences.
import SwiftUI

struct PanelSettingsView: View {
  @ObservedObject var preferences: MemoryPreferences
  @ObservedObject var login: LoginSettings
  let inset: CGFloat

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Picker("settings.language", selection: $preferences.language) {
          Text("language.system").tag(AppLanguage.system)
          Text(verbatim: "English").tag(AppLanguage.english)
          Text(verbatim: "Français").tag(AppLanguage.french)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("settings-language-picker")
        Picker("settings.status-display", selection: $preferences.display) {
          Text("display.icon").tag(MemoryDisplay.icon)
          Text("display.used").tag(MemoryDisplay.used)
          Text("display.available").tag(MemoryDisplay.available)
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("settings-display-picker")
        SystemThresholdSettings(preferences: preferences)
        Divider()
        appThresholdSettings
        Divider()
        Toggle(
          "settings.launch-at-login",
          isOn: Binding(
            get: { login.isRegistered },
            set: { value in login.setRegistered(value) }
          )
        )
        .toggleStyle(.switch)
        .accessibilityIdentifier("settings-login-toggle")
        if login.status == .requiresApproval {
          Text("settings.approval").font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("settings-login-approval-label")
          Button("settings.system") { login.openSystemSettings() }
            .accessibilityIdentifier("settings-open-system-btn")
        }
        if login.didFail {
          Text("settings.failed").font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("settings-login-error-label")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(inset)
    }
  }

  private var appThresholdSettings: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("settings.app-thresholds").font(.callout.weight(.semibold))
      Stepper(
        value: Binding(
          get: { preferences.thresholds.warningGB }, set: { value in preferences.setWarning(value) }
        ),
        in: AppMemoryThresholds.minimumGB...(preferences.thresholds.criticalGB - 1)
      ) {
        Label {
          Text("settings.warning \(preferences.thresholds.warningGB)")
        } icon: {
          Image(systemName: "circle.fill").foregroundStyle(.orange)
        }
      }
      .accessibilityIdentifier("settings-app-warning-stepper")
      Stepper(
        value: Binding(
          get: { preferences.thresholds.criticalGB },
          set: { value in preferences.setCritical(value) }),
        in: (preferences.thresholds.warningGB + 1)...AppMemoryThresholds.maximumGB
      ) {
        Label {
          Text("settings.critical \(preferences.thresholds.criticalGB)")
        } icon: {
          Image(systemName: "circle.fill").foregroundStyle(.red)
        }
      }
      .accessibilityIdentifier("settings-app-critical-stepper")
    }
  }
}
