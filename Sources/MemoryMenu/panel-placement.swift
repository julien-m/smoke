// Anchors the panel within the screen that owns the clicked status item.
import CoreGraphics

enum PanelPlacement {
  static let preferredSize = CGSize(width: 328, height: 488)
  private static let gap: CGFloat = 4

  static func frame(anchor: CGRect, visibleFrame: CGRect) -> CGRect? {
    let top = min(anchor.minY, visibleFrame.maxY) - gap
    let width = min(preferredSize.width, visibleFrame.width)
    let height = min(preferredSize.height, top - visibleFrame.minY)
    guard width > 0, height > 0 else { return nil }
    let centeredX = anchor.midX - width / 2
    let x = min(max(centeredX, visibleFrame.minX), visibleFrame.maxX - width)
    return CGRect(x: x, y: top - height, width: width, height: height)
  }
}
