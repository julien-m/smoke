// Hosts a screen-constrained panel under the macOS menu bar item.
import AppKit
import Combine
import ServiceManagement
import SwiftUI

@main
@MainActor
enum MemoryMenu {
  static func main() {
    let workspace = NSWorkspace.shared
    let application = NSApplication.shared
    let model = PanelModel(
      workspace: workspace,
      sampler: MemorySampler(),
      actions: AppActions(workspace: workspace)
    )
    let delegate = MenuDelegate(
      model: model, login: LoginSettings(service: .mainApp),
      preferences: MemoryPreferences(defaults: .standard)
    )
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
    withExtendedLifetime(delegate) {}
  }
}

@MainActor
final class MenuDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private let model: PanelModel
  private let login: LoginSettings
  private let preferences: MemoryPreferences
  private var monitor: SystemMemoryMonitor?
  private var preferenceObservation: AnyCancellable?
  private var badgeWidth: CGFloat = 0
  private var systemReading: SystemMemory?
  private var systemPressure: MemoryLevel = .normal
  private var panel: MenuPanel?
  private var item: NSStatusItem?

  init(model: PanelModel, login: LoginSettings, preferences: MemoryPreferences) {
    self.model = model
    self.login = login
    self.preferences = preferences
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    self.item = item
    item.button?.imagePosition = .imageOnly
    item.button?.setAccessibilityIdentifier("smoke-status-btn")
    item.button?.target = self
    item.button?.action = #selector(togglePanel)
    startSystemIndicator()
  }

  @objc func togglePanel() {
    if let panel, panel.isVisible {
      panel.close()
      return
    }
    guard let frame = frameBelowStatusItem() else { return }
    let panel = panel ?? makePanel()
    self.panel = panel
    panel.setFrame(frame, display: false)
    login.refresh()
    monitor?.refresh()
    model.open()
    panel.makeKeyAndOrderFront(nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    // Defer closing until AppKit has delivered any click on the status button.
    Task { [weak self] in
      guard let panel = self?.panel, panel.isVisible, !panel.isKeyWindow else { return }
      panel.close()
    }
  }

  func windowWillClose(_ notification: Notification) {
    model.close()
  }

  func applicationDidChangeScreenParameters(_ notification: Notification) {
    repositionPanel()
  }

  private func repositionPanel() {
    guard let panel, panel.isVisible else { return }
    if let frame = frameBelowStatusItem() {
      panel.setFrame(frame, display: true)
    } else {
      panel.close()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    monitor?.stop()
  }

  private func startSystemIndicator() {
    let monitor = SystemMemoryMonitor(
      total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(getpagesize())
    ) { [weak self] reading, level in
      guard let self else { return }
      systemReading = reading
      systemPressure = level
      updateStatusItem(
        display: preferences.display, thresholds: preferences.systemThresholds,
        language: preferences.language)
    }
    self.monitor = monitor
    preferenceObservation = Publishers.CombineLatest3(
      preferences.$display, preferences.$systemThresholds, preferences.$language
    ).sink { [weak self] display, thresholds, language in
      self?.updateStatusItem(display: display, thresholds: thresholds, language: language)
    }
    monitor.start()
  }

  private func updateStatusItem(
    display: MemoryDisplay, thresholds: SystemMemoryThresholds, language: AppLanguage
  ) {
    guard let item, let button = item.button else { return }
    let measuredLevel =
      systemReading.map { thresholds.level(usedPercent: $0.usedPercent) } ?? .normal
    let level = display == .icon ? max(measuredLevel, systemPressure) : measuredLevel
    let percent: Int? =
      switch display {
      case .icon: nil
      case .used: systemReading?.usedPercent
      case .available: systemReading?.availablePercent
      }
    let text = percent.map { percentage($0, language: language) } ?? ""
    let image = StatusBadge.image(text: text, level: level)
    item.length = NSStatusItem.variableLength
    button.image = image
    button.toolTip = statusDescription(language: language)
    button.setAccessibilityLabel(button.toolTip)
    let width = image?.size.width ?? 0
    if badgeWidth != width, panel?.isVisible == true {
      Task { [weak self] in self?.repositionPanel() }
    }
    badgeWidth = width
  }

  private func percentage(_ value: Int, language: AppLanguage) -> String {
    let ratio = Double(value) / Double(SystemMemoryThresholds.percentMaximum)
    return ratio.formatted(.percent.precision(.fractionLength(0)).locale(language.locale))
  }

  private func statusDescription(language: AppLanguage) -> String {
    guard let reading = systemReading else { return language.localized("panel.title") }
    return String.localizedStringWithFormat(
      language.localized("status.summary"),
      percentage(reading.usedPercent, language: language),
      percentage(reading.availablePercent, language: language)
    )
  }

  private func frameBelowStatusItem() -> CGRect? {
    guard let button = item?.button, let window = button.window else { return nil }
    let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
    let screen =
      NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
      ?? window.screen
    return screen.flatMap { PanelPlacement.frame(anchor: anchor, visibleFrame: $0.visibleFrame) }
  }

  private func makePanel() -> MenuPanel {
    let panel = MenuPanel(
      contentRect: CGRect(origin: .zero, size: PanelPlacement.preferredSize),
      styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.identifier = NSUserInterfaceItemIdentifier("memory-menu.panel")
    panel.isReleasedWhenClosed = false
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .windowBackgroundColor
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.titlebarSeparatorStyle = .none
    panel.animationBehavior = .none
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.delegate = self
    let host = NSHostingController(
      rootView: PanelView(model: model, login: login, preferences: preferences) {
        NSApplication.shared.terminate(nil)
      })
    // The monitor determines the maximum size, including when the usable height is small.
    host.sizingOptions = []
    panel.contentViewController = host
    return panel
  }
}

private final class MenuPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override func cancelOperation(_ sender: Any?) { close() }
}
