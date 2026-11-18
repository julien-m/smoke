// Requests application lifecycle changes and waits on termination without polling.
import AppKit
import OSLog

enum AppAction {
  case quit, forceQuit, restart
}

enum AppActionError: Error {
  case appChanged, requestRejected, terminationTimeout, launchFailed
}

@MainActor
final class AppActions {
  private let workspace: NSWorkspace
  private let logger = Logger(subsystem: "local.memory-menu", category: "lifecycle")
  private static let quitTimeout: Duration = .seconds(20)

  init(workspace: NSWorkspace) {
    self.workspace = workspace
  }

  func perform(_ action: AppAction, on app: NSRunningApplication) async throws {
    guard !app.isTerminated,
      workspace.runningApplications.contains(app),
      app.processIdentifier != NSRunningApplication.current.processIdentifier
    else { throw AppActionError.appChanged }
    let restartURL = app.bundleURL
    if action == .restart, restartURL == nil { throw AppActionError.launchFailed }

    // Register before sending the quit request so fast exits cannot be missed.
    let termination = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let observation = app.observe(\.isTerminated, options: [.initial, .new]) { app, _ in
      if app.isTerminated { termination.continuation.yield(()) }
    }
    defer {
      observation.invalidate()
      termination.continuation.finish()
    }
    let requested = action == .forceQuit ? app.forceTerminate() : app.terminate()
    guard requested || app.isTerminated else { throw AppActionError.requestRejected }
    guard await waitForExit(termination.stream), app.isTerminated else {
      throw AppActionError.terminationTimeout
    }
    if action == .restart, let restartURL {
      try await reopen(restartURL)
    }
  }

  private func waitForExit(_ termination: AsyncStream<Void>) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        var events = termination.makeAsyncIterator()
        return await events.next() != nil
      }
      group.addTask {
        // A single timeout bounds the wait for save dialogs and unresponsive apps.
        try? await Task.sleep(for: Self.quitTimeout)
        return false
      }
      let didExit = await group.next() ?? false
      group.cancelAll()
      return didExit
    }
  }

  private func reopen(_ url: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    // Preserve the selected instance when another instance of the same bundle is running.
    configuration.createsNewApplicationInstance = true
    do {
      _ = try await workspace.openApplication(at: url, configuration: configuration)
    } catch {
      logger.error("App relaunch failed: \(String(describing: error), privacy: .private)")
      throw AppActionError.launchFailed
    }
  }
}
