// swift-tools-version: 6.0
// Defines the macOS menu bar executable and its Darwin sampling boundary.
import PackageDescription

let package = Package(
  name: "Smoke",
  platforms: [.macOS(.v15)],
  products: [.executable(name: "memory-menu", targets: ["MemoryMenu"])],
  targets: [
    .target(name: "CoalitionReader"),
    .executableTarget(name: "MemoryMenu", dependencies: ["CoalitionReader"]),
    .testTarget(name: "SmokeTests", dependencies: ["MemoryMenu"]),
  ]
)
