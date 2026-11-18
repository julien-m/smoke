// Reflects the actual macOS registration state for launch at login.
import Combine
import OSLog
import ServiceManagement

@MainActor
final class LoginSettings: ObservableObject {
  @Published private(set) var status: SMAppService.Status = .notRegistered
  @Published private(set) var didFail = false

  private let service: SMAppService
  private let logger = Logger(subsystem: "local.memory-menu", category: "login")

  init(service: SMAppService) {
    self.service = service
  }

  var isRegistered: Bool {
    status == .enabled || status == .requiresApproval
  }

  func refresh() {
    status = service.status
  }

  func setRegistered(_ enabled: Bool) {
    refresh()
    didFail = false
    guard enabled != isRegistered else { return }
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
    } catch {
      logger.error("Could not update login item: \(String(describing: error), privacy: .private)")
      didFail = true
    }
    // Service Management owns the setting and may require user approval.
    refresh()
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
