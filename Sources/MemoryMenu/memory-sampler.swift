// Samples app totals and resolves process membership on a background executor.
import CoalitionReader
import Darwin
import Foundation

struct AppMemory: Sendable {
  let coalition: UInt64
  let bytes: UInt64?
}

struct ProcessMemory: Identifiable, Sendable {
  let id: pid_t
  let name: String
  let bytes: UInt64?
}

struct MemorySample: Sendable {
  let applications: [pid_t: AppMemory]
  let processes: [ProcessMemory]?
}

actor MemorySampler {
  private let readUsage: CoalitionUsageReader?

  init(version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) {
    // The private layout was verified on 26.5. Keep sampling fail-closed on other versions.
    readUsage =
      version.majorVersion == 26 && version.minorVersion == 5
      ? mm_resolve_usage_reader() : nil
  }

  func sample(applications: [pid_t], expanded: pid_t?) -> MemorySample {
    // Coalition membership uses the same unverified private ABI as the aggregate.
    guard let readUsage else {
      return MemorySample(applications: [:], processes: nil)
    }
    var results: [pid_t: AppMemory] = [:]
    var totals: [UInt64: AppMemory] = [:]
    for pid in applications {
      guard !Task.isCancelled else { break }
      var coalition: UInt64 = 0
      guard mm_resource_coalition(pid, &coalition) else { continue }
      if let existing = totals[coalition] {
        results[pid] = existing
        continue
      }
      var bytes: UInt64 = 0
      let value = AppMemory(
        coalition: coalition,
        bytes: mm_coalition_footprint(readUsage, coalition, &bytes) ? bytes : nil
      )
      totals[coalition] = value
      results[pid] = value
    }
    let processes = expanded.flatMap { results[$0] }.flatMap { members(of: $0.coalition) }
    return MemorySample(applications: results, processes: processes)
  }

  private func members(of coalition: UInt64) -> [ProcessMemory]? {
    guard let pids = listProcessIDs() else { return nil }
    var matches: [ProcessMemory] = []
    for pid in pids {
      guard !Task.isCancelled else { return nil }
      var current: UInt64 = 0
      guard pid > 0, mm_resource_coalition(pid, &current), current == coalition else { continue }
      if let process = readProcess(pid, coalition: coalition) { matches.append(process) }
    }
    return matches.sorted { ($0.bytes ?? 0, $0.id) > ($1.bytes ?? 0, $1.id) }
  }

  private func listProcessIDs() -> [pid_t]? {
    let count = Int(proc_listallpids(nil, 0))
    let processGrowthAllowance = 64
    let maxCapacity = Int(Int32.max) / MemoryLayout<pid_t>.size
    guard count > 0, count <= maxCapacity - processGrowthAllowance else { return nil }
    // Allow a small batch of new processes between the size query and the snapshot.
    var pids = [pid_t](repeating: 0, count: count + processGrowthAllowance)
    let filled = pids.withUnsafeMutableBufferPointer {
      proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
    }
    guard filled > 0, filled < pids.count else { return nil }
    return Array(pids.prefix(Int(filled)))
  }

  private func readProcess(_ pid: pid_t, coalition: UInt64) -> ProcessMemory? {
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let count = proc_pidpath(pid, &path, UInt32(path.count))
    var bytes: UInt64 = 0
    let footprint = mm_process_footprint(pid, &bytes) ? bytes : nil
    var current: UInt64 = 0
    // Recheck membership after reading the process in case it exited or its PID was reused.
    guard mm_resource_coalition(pid, &current), current == coalition else { return nil }
    let executable = String(
      decoding: path.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
    let name = count > 0 ? URL(fileURLWithPath: executable).lastPathComponent : String(pid)
    return ProcessMemory(id: pid, name: name, bytes: footprint)
  }
}
