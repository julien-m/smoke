// Estimates physical memory usage and listens for macOS memory pressure.
import Darwin
import Foundation

struct SystemMemory {
  let usedRatio: Double
  var usedPercent: Int {
    Int((usedRatio * Double(SystemMemoryThresholds.percentMaximum)).rounded())
  }
  var availablePercent: Int { SystemMemoryThresholds.percentMaximum - usedPercent }

  static func read(total: UInt64, pageSize: UInt64) -> Self? {
    var info = vm_statistics64_data_t()
    let capacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
    var count = mach_msg_type_number_t(capacity)
    let host = mach_host_self()
    defer { mach_port_deallocate(mach_task_self_, host) }
    let result = withUnsafeMutablePointer(to: &info) { buffer in
      buffer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
        host_statistics64(host, HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS, count == capacity, total > 0, pageSize > 0 else { return nil }
    // File-backed cache is reclaimable. Count anonymous, wired and compressed resident pages.
    let charged =
      UInt64(info.internal_page_count) + UInt64(info.wire_count)
      + UInt64(info.compressor_page_count)
    let usedPages = charged - min(charged, UInt64(info.purgeable_count))
    return Self(usedRatio: min(1, Double(usedPages) * Double(pageSize) / Double(total)))
  }
}

@MainActor
final class SystemMemoryMonitor {
  private let total: UInt64
  private let pageSize: UInt64
  private let onChange: (SystemMemory?, MemoryLevel) -> Void
  private var pressure: MemoryLevel = .normal
  private var source: DispatchSourceMemoryPressure?
  private var clock: DispatchSourceTimer?

  // A single host query keeps the idle percentage reasonably fresh without inventorying processes.
  private static let interval: DispatchTimeInterval = .seconds(60)
  private static let tolerance: DispatchTimeInterval = .seconds(10)

  init(total: UInt64, pageSize: UInt64, onChange: @escaping (SystemMemory?, MemoryLevel) -> Void) {
    self.total = total
    self.pageSize = pageSize
    self.onChange = onChange
  }

  func start() {
    guard source == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(
      eventMask: [.normal, .warning, .critical], queue: .main)
    self.source = source
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.receivePressure() }
    }
    source.activate()
    let clock = DispatchSource.makeTimerSource(queue: .main)
    self.clock = clock
    clock.schedule(
      deadline: .now() + Self.interval, repeating: Self.interval, leeway: Self.tolerance)
    clock.setEventHandler { [weak self] in
      MainActor.assumeIsolated { self?.refresh() }
    }
    clock.activate()
    refresh()
  }

  func stop() {
    clock?.cancel()
    clock = nil
    source?.cancel()
    source = nil
  }

  func refresh() {
    let reading = SystemMemory.read(total: total, pageSize: pageSize)
    onChange(reading, pressure)
  }

  private func receivePressure() {
    guard let event = source?.data else { return }
    if event.contains(.critical) {
      pressure = .critical
    } else if event.contains(.warning) {
      pressure = .warning
    } else {
      pressure = .normal
    }
    refresh()
  }
}
