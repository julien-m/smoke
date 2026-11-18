// Owns the visible sampling session and the panel's action state.
import AppKit
import Combine

struct AppRow: Identifiable {
  let app: NSRunningApplication
  let bytes: UInt64?

  var id: NSRunningApplication { app }
  var name: String { app.localizedName ?? app.bundleIdentifier ?? String(app.processIdentifier) }
}

struct ActionRequest {
  let action: AppAction
  let app: NSRunningApplication
  let name: String
}

@MainActor
final class PanelModel: ObservableObject {
  @Published private(set) var apps: [AppRow] = []
  @Published private(set) var processes: [ProcessMemory]?
  @Published private(set) var isLoadingProcesses = false
  @Published private(set) var expanded: NSRunningApplication?
  @Published private(set) var sampledAt: Date?
  @Published private(set) var busyApp: NSRunningApplication?
  @Published private(set) var actionError: AppActionError?
  @Published var confirmation: ActionRequest?
  @Published private(set) var showsSettings = false

  private let workspace: NSWorkspace
  private let sampler: MemorySampler
  private let actions: AppActions
  private var clock: Timer?
  private var applicationObservation: NSKeyValueObservation?
  private var workspaceUpdate: Task<Void, Never>?
  private var sampling: Task<Void, Never>?
  private var visible = false

  // A visible panel needs fresh totals even when the app inventory hasn't changed.
  private static let refreshInterval: TimeInterval = 5
  private static let refreshTolerance: TimeInterval = 1
  private static let workspaceDebounce: Duration = .milliseconds(250)

  init(workspace: NSWorkspace, sampler: MemorySampler, actions: AppActions) {
    self.workspace = workspace
    self.sampler = sampler
    self.actions = actions
  }

  static func visibleApps(in workspace: NSWorkspace) -> [NSRunningApplication] {
    workspace.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
  }

  func open() {
    guard !visible else { return }
    visible = true
    startSampling()
  }

  func close() {
    visible = false
    showsSettings = false
    stopSampling()
  }

  func toggleSettings() {
    showsSettings.toggle()
    if showsSettings {
      stopSampling()
    } else if visible {
      startSampling()
    }
  }

  private func startSampling() {
    applicationObservation = workspace.observe(\.runningApplications, options: [.new]) {
      [weak self] _, _ in
      Task { @MainActor in self?.queueWorkspaceUpdate() }
    }
    let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
    timer.tolerance = Self.refreshTolerance
    RunLoop.main.add(timer, forMode: .common)
    clock = timer
    refresh()
  }

  private func stopSampling() {
    clock?.invalidate()
    clock = nil
    applicationObservation?.invalidate()
    applicationObservation = nil
    workspaceUpdate?.cancel()
    workspaceUpdate = nil
    sampling?.cancel()
    sampling = nil
    expanded = nil
    processes = nil
    isLoadingProcesses = false
    confirmation = nil
  }

  func refresh(replacePending: Bool = false) {
    guard visible, !showsSettings, replacePending || sampling == nil else { return }
    sampling?.cancel()
    let running = Self.visibleApps(in: workspace)
    if let expanded, !running.contains(expanded) {
      self.expanded = nil
      processes = nil
      isLoadingProcesses = false
    }
    let selection = expanded?.processIdentifier
    let pids = running.map(\.processIdentifier)
    sampling = Task { [weak self, sampler] in
      let sample = await sampler.sample(applications: pids, expanded: selection)
      guard !Task.isCancelled, let self else { return }
      self.publish(sample, for: running)
      self.sampling = nil
    }
  }

  func toggleDetails(for app: NSRunningApplication) {
    expanded = expanded == app ? nil : app
    processes = nil
    isLoadingProcesses = expanded != nil
    refresh(replacePending: true)
  }

  func request(_ action: AppAction, row: AppRow) {
    guard busyApp == nil else { return }
    let request = ActionRequest(action: action, app: row.app, name: row.name)
    if action == .forceQuit {
      confirmation = request
    } else {
      perform(request)
    }
  }

  func perform(_ request: ActionRequest) {
    guard busyApp == nil else { return }
    confirmation = nil
    actionError = nil
    busyApp = request.app
    // The action survives popover dismissal, including when a document prompts to save.
    Task {
      defer {
        busyApp = nil
        refresh(replacePending: true)
      }
      do {
        try await actions.perform(request.action, on: request.app)
      } catch let error as AppActionError {
        actionError = error
      } catch {
        actionError = .requestRejected
      }
    }
  }

  func dismissError() {
    actionError = nil
  }

  private func queueWorkspaceUpdate() {
    guard visible, !showsSettings else { return }
    workspaceUpdate?.cancel()
    workspaceUpdate = Task { [weak self] in
      try? await Task.sleep(for: Self.workspaceDebounce)
      guard !Task.isCancelled else { return }
      self?.refresh(replacePending: true)
    }
  }

  private func publish(_ sample: MemorySample, for running: [NSRunningApplication]) {
    apps = running.filter { !$0.isTerminated }.map {
      AppRow(app: $0, bytes: sample.applications[$0.processIdentifier]?.bytes)
    }.sorted {
      switch ($0.bytes, $1.bytes) {
      case (let lhs?, let rhs?) where lhs != rhs: lhs > rhs
      case (_?, nil): true
      case (nil, _?): false
      default: $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
    }
    processes = sample.processes
    isLoadingProcesses = false
    sampledAt = .now
  }
}
