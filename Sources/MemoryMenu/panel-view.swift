// Renders the menu bar popover, including actions available without expanding a row.
import AppKit
import SwiftUI

private enum PanelLayout {
  static let inset: CGFloat = 16
  static let rowInset: CGFloat = 8
  static let iconSize: CGFloat = 24
  static let actionSize: CGFloat = 28
  static let actionGap: CGFloat = 4
  static let trailingWidth = 3 * actionSize + 2 * actionGap
}

struct PanelView: View {
  @ObservedObject var model: PanelModel
  @ObservedObject var login: LoginSettings
  @ObservedObject var preferences: MemoryPreferences
  let quitPanel: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      notice
      if model.showsSettings {
        settings
      } else if model.apps.isEmpty {
        emptyState
      } else {
        appList
      }
      Divider()
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .environment(\.locale, preferences.language.locale)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Text(model.showsSettings ? "settings.title" : "panel.heading")
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
      Spacer(minLength: 8)
      if !model.showsSettings {
        Button {
          model.refresh(replacePending: true)
        } label: {
          Label("panel.refresh", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
            .frame(width: PanelLayout.actionSize, height: PanelLayout.actionSize)
        }
        .buttonStyle(.borderless)
        .help(Text("panel.refresh"))
      }
      Button {
        model.toggleSettings()
        if model.showsSettings { login.refresh() }
      } label: {
        Label(
          model.showsSettings ? "settings.back" : "settings.title",
          systemImage: model.showsSettings ? "arrow.left" : "gearshape"
        )
        .labelStyle(.iconOnly)
        .frame(width: PanelLayout.actionSize, height: PanelLayout.actionSize)
      }
      .buttonStyle(.borderless)
      .help(Text(model.showsSettings ? "settings.back" : "settings.title"))
    }
    .padding(.horizontal, PanelLayout.inset)
    .padding(.vertical, 4)
  }

  @ViewBuilder private var notice: some View {
    if let confirmation = model.confirmation {
      VStack(alignment: .leading, spacing: 8) {
        Text("action.confirm \(confirmation.name)").font(.callout.weight(.semibold))
        Text("action.unsaved").font(.caption).foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Spacer()
          Button("action.cancel") { model.confirmation = nil }
          Button("action.force", role: .destructive) { model.perform(confirmation) }
            .tint(.red)
        }
        .buttonStyle(.bordered)
      }
      .padding(PanelLayout.inset)
      Divider()
    } else if let error = model.actionError {
      HStack(spacing: 8) {
        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
        Text(error.message).font(.caption)
        Spacer()
        Button("action.dismiss", systemImage: "xmark", action: model.dismissError)
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
      }
      .padding(PanelLayout.inset)
      Divider()
    }
  }

  private var settings: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Picker("settings.language", selection: $preferences.language) {
          Text("language.system").tag(AppLanguage.system)
          Text(verbatim: "English").tag(AppLanguage.english)
          Text(verbatim: "Français").tag(AppLanguage.french)
        }
        .pickerStyle(.menu)
        Picker("settings.status-display", selection: $preferences.display) {
          Text("display.icon").tag(MemoryDisplay.icon)
          Text("display.used").tag(MemoryDisplay.used)
          Text("display.available").tag(MemoryDisplay.available)
        }
        .pickerStyle(.menu)
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
        if login.status == .requiresApproval {
          Text("settings.approval").font(.caption).foregroundStyle(.secondary)
          Button("settings.system") { login.openSystemSettings() }
        }
        if login.didFail {
          Text("settings.failed").font(.caption).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(PanelLayout.inset)
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
    }
  }

  private var emptyState: some View {
    Group {
      if model.sampledAt == nil {
        ProgressView().controlSize(.small)
      } else {
        Text("panel.empty").foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var appList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 4) {
        ForEach(model.apps) { row in
          AppRowView(
            row: row, isExpanded: model.expanded == row.app, isBusy: model.busyApp == row.app,
            canAct: model.busyApp == nil,
            memoryLevel: preferences.thresholds.level(bytes: row.bytes),
            toggle: { model.toggleDetails(for: row.app) },
            action: { model.request($0, row: row) }
          )
          if model.expanded == row.app {
            processList(model.processes)
          }
        }
      }
      .padding(PanelLayout.rowInset)
    }
  }

  private func processList(_ processes: [ProcessMemory]?) -> some View {
    LazyVStack(alignment: .leading, spacing: 4) {
      if model.isLoadingProcesses {
        Text("process.loading").font(.caption).foregroundStyle(.secondary)
      } else if let processes, !processes.isEmpty {
        Text("process.count \(processes.count)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(processes) { process in
          HStack(spacing: 8) {
            Text(process.name)
              .lineLimit(1)
              .help(process.name)
            Spacer(minLength: 8)
            Text("process.pid \(String(process.id))")
              .foregroundStyle(.secondary)
            FootprintLabel(bytes: process.bytes)
              .frame(minWidth: 64, alignment: .trailing)
          }
          .font(.caption)
        }
      } else {
        Text("process.unavailable").font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    .padding(.leading, 24)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      if !model.showsSettings, let date = model.sampledAt {
        Text(
          "panel.updated \(date.formatted(.dateTime.hour().minute().second().locale(preferences.language.locale)))"
        )
      }
      Spacer()
      Button("panel.quit", action: quitPanel)
        .buttonStyle(.borderless)
        .disabled(model.busyApp != nil)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, PanelLayout.inset)
    .padding(.vertical, 8)
  }
}

private struct AppRowView: View {
  let row: AppRow
  let isExpanded: Bool
  let isBusy: Bool
  let canAct: Bool
  let memoryLevel: MemoryLevel
  let toggle: () -> Void
  let action: (AppAction) -> Void
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 8) {
      Button(action: toggle) {
        HStack(spacing: 8) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 12)
            .accessibilityHidden(true)
          if let icon = row.app.icon {
            Image(nsImage: icon).resizable().scaledToFit()
              .frame(width: PanelLayout.iconSize, height: PanelLayout.iconSize)
              .accessibilityHidden(true)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
              .lineLimit(1)
              .truncationMode(.tail)
              .help(row.name)
            if memoryLevel != .normal {
              Capsule()
                .fill(memoryLevel == .critical ? Color.red : .orange)
                .frame(width: 16, height: 2)
                .accessibilityLabel(
                  Text(memoryLevel == .critical ? "memory.critical" : "memory.warning"))
            }
          }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityHint(Text(isExpanded ? "process.collapse" : "process.expand"))
      trailingContent
        .frame(width: PanelLayout.trailingWidth, alignment: .trailing)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      hovered || isExpanded ? Color.primary.opacity(0.055) : .clear,
      in: RoundedRectangle(cornerRadius: 8)
    )
    .contentShape(Rectangle())
    .onHover { hovered = $0 }
    .contextMenu {
      Button("action.quit") { action(.quit) }.disabled(!canAct)
      Button("action.force", role: .destructive) { action(.forceQuit) }.disabled(!canAct)
      Button("action.restart") { action(.restart) }.disabled(!canAct || row.app.bundleURL == nil)
    }
    .accessibilityAction(named: Text("action.quit")) { if canAct { action(.quit) } }
    .accessibilityAction(named: Text("action.force")) { if canAct { action(.forceQuit) } }
    .accessibilityAction(named: Text("action.restart")) {
      if canAct, row.app.bundleURL != nil { action(.restart) }
    }
  }

  @ViewBuilder private var trailingContent: some View {
    if isBusy {
      ProgressView().controlSize(.small)
    } else if hovered {
      HStack(spacing: PanelLayout.actionGap) {
        actionButton(.quit, title: "action.quit", icon: "rectangle.portrait.and.arrow.right")
        actionButton(.forceQuit, title: "action.force", icon: "xmark.octagon", destructive: true)
        actionButton(.restart, title: "action.restart", icon: "arrow.clockwise")
          .disabled(row.app.bundleURL == nil)
      }
      .disabled(!canAct)
    } else {
      FootprintLabel(bytes: row.bytes)
    }
  }

  private func actionButton(
    _ kind: AppAction, title: LocalizedStringKey, icon: String, destructive: Bool = false
  ) -> some View {
    Button {
      action(kind)
    } label: {
      Label(title, systemImage: icon)
        .labelStyle(.iconOnly)
        .foregroundStyle(destructive ? Color.red : .primary)
        .frame(width: PanelLayout.actionSize, height: PanelLayout.actionSize)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(Text(title))
  }
}

private struct FootprintLabel: View {
  let bytes: UInt64?
  var body: some View {
    Group {
      if let bytes {
        Text(Int64(clamping: bytes), format: .byteCount(style: .file))
          .help(bytes.formatted(.number))
      } else {
        Text("memory.unavailable").foregroundStyle(.secondary)
      }
    }
    .monospacedDigit()
    .lineLimit(1)
  }
}

extension AppActionError {
  fileprivate var message: LocalizedStringKey {
    switch self {
    case .appChanged: "error.app-changed"
    case .requestRejected: "error.request-rejected"
    case .terminationTimeout: "error.timeout"
    case .launchFailed: "error.launch"
    }
  }
}
