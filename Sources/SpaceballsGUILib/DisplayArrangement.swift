import CoreGraphics

/// A physical direction on the user's display arrangement.
public enum ArrangementDirection: Equatable {
  case up
  case down
  case left
  case right
}

/// The physical layout of the connected displays, in AppKit global screen
/// coordinates (origin bottom-left, y increases upward — `NSScreen.frame`).
///
/// Resolves "the display in that direction" for Shift+arrow navigation: the
/// nearest display whose center lies in the requested direction, preferring
/// straight-ahead candidates over diagonal ones, while keeping diagonal
/// neighbors reachable when nothing lies squarely in the direction.
public struct DisplayArrangement: Equatable {
  public struct Display: Equatable {
    public let uuid: String
    public let frame: CGRect

    public init(uuid: String, frame: CGRect) {
      self.uuid = uuid
      self.frame = frame
    }
  }

  public let displays: [Display]

  public init(displays: [Display]) {
    self.displays = displays
  }

  /// Weight applied to perpendicular offset when scoring candidates. Higher
  /// values favor straight-ahead displays over nearer diagonal ones.
  private static let perpendicularPenalty: CGFloat = 2

  public func neighborUUID(of uuid: String, direction: ArrangementDirection) -> String? {
    guard let origin = displays.first(where: { $0.uuid == uuid }) else { return nil }
    let ox = origin.frame.midX
    let oy = origin.frame.midY

    var best: (uuid: String, score: CGFloat)?
    for candidate in displays where candidate.uuid != uuid {
      let dx = candidate.frame.midX - ox
      let dy = candidate.frame.midY - oy

      // Axial component must point in the requested direction (y-up coords).
      let (axial, perpendicular): (CGFloat, CGFloat) =
        switch direction {
        case .right: (dx, dy)
        case .left: (-dx, dy)
        case .up: (dy, dx)
        case .down: (-dy, dx)
        }
      guard axial > 0 else { continue }

      let score = axial + Self.perpendicularPenalty * abs(perpendicular)
      if best == nil || score < best!.score {
        best = (candidate.uuid, score)
      }
    }
    return best?.uuid
  }
}
