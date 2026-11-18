// Draws an explicit status image so macOS preserves warning colors and text contrast.
import AppKit

@MainActor
enum StatusBadge {
  private static let symbol = NSImage(
    systemSymbolName: "memorychip", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
  private static let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
  private static let height: CGFloat = 18
  private static let inset: CGFloat = 4
  private static let gap: CGFloat = 4

  static func image(text: String, level: MemoryLevel) -> NSImage? {
    guard let symbol else { return nil }
    let text = NSAttributedString(
      string: text, attributes: [.foregroundColor: NSColor.black, .font: font])
    let textWidth = text.length == 0 ? 0 : ceil(text.size().width) + gap
    let size = NSSize(width: 2 * inset + ceil(symbol.size.width) + textWidth, height: height)
    let image = NSImage(size: size, flipped: false) { bounds in
      if level != .normal {
        let background = level == .critical ? NSColor.systemRed : NSColor.systemOrange
        background.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
      }
      symbol.draw(
        at: NSPoint(x: inset, y: (height - symbol.size.height) / 2),
        from: .zero, operation: .sourceOver, fraction: 1)
      if text.length > 0 {
        text.draw(
          at: NSPoint(
            x: inset + ceil(symbol.size.width) + gap,
            y: (height - text.size().height) / 2))
      }
      return true
    }
    // In the normal state, macOS adapts the monochrome template to the menu bar appearance.
    image.isTemplate = level == .normal
    return image
  }
}
