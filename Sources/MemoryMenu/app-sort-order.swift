// Orders app snapshots without querying processes or changing the selected app.
import Darwin
import Foundation

struct AppSortKey {
  let name: String
  let bytes: UInt64?
  let pid: pid_t
}

enum AppSortOrder {
  case memory
  case name

  var alternate: Self { self == .memory ? .name : .memory }

  func precedes(_ lhs: AppSortKey, _ rhs: AppSortKey) -> Bool {
    if self == .memory {
      switch (lhs.bytes, rhs.bytes) {
      case (let left?, let right?) where left != right: return left > right
      case (_?, nil): return true
      case (nil, _?): return false
      default: break
      }
    }
    let names = lhs.name.localizedStandardCompare(rhs.name)
    // Duplicate display names are common, so ties need a stable order across samples.
    return names == .orderedSame ? lhs.pid < rhs.pid : names == .orderedAscending
  }
}
