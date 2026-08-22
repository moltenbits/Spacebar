import CoreGraphics
import Foundation

/// Decides where, if anywhere, activating something should warp the cursor
/// (issue #17). Pure — callers supply the cursor's global position and
/// display, the activation target's display, and the activated window's frame.
/// Callers also gate on the "Move pointer to the activated window" setting;
/// the planner only reasons about geometry.
public enum CursorWarpPlanner {

  public enum Destination: Equatable {
    /// The activated window's center, in global CG coordinates (top-left
    /// origin, matching `kCGWindowBounds`).
    case windowCenter(CGPoint)
    /// The center of the display with this CGS UUID — used when there is no
    /// window to aim at (an empty Space) or its frame is unknown.
    case displayCenter(String)
  }

  /// With a known window frame the pointer goes to the window's center, on the
  /// same display or another — a very large display loses the pointer as
  /// easily as a second one. It stays put only when it is already over the
  /// window, where a jump to center would be a gratuitous hop (and an unknown
  /// cursor position can't prove that, so it warps). Without a frame the only
  /// way the pointer is "lost" is by display, so it recenters on the target
  /// display when the cursor is on a different, known display; a same-display
  /// Space switch with nothing to aim at leaves it alone.
  public static func destination(
    cursorPosition: CGPoint?,
    cursorDisplayUUID: String?, targetDisplayUUID: String?,
    windowFrame: CGRect?
  ) -> Destination? {
    if let windowFrame {
      if let cursorPosition, windowFrame.contains(cursorPosition) { return nil }
      return .windowCenter(CGPoint(x: windowFrame.midX, y: windowFrame.midY))
    }
    guard let cursorDisplayUUID, let targetDisplayUUID, cursorDisplayUUID != targetDisplayUUID
    else { return nil }
    return .displayCenter(targetDisplayUUID)
  }
}
