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

    var best: (uuid: String, clearsEdge: Bool, score: CGFloat)?
    for candidate in displays where candidate.uuid != uuid {
      let cx = candidate.frame.midX
      let cy = candidate.frame.midY

      // Axial component must point in the requested direction (y-up coords).
      let (axial, perpendicular): (CGFloat, CGFloat) =
        switch direction {
        case .right: (cx - ox, cy - oy)
        case .left: (ox - cx, cy - oy)
        case .up: (cy - oy, cx - ox)
        case .down: (oy - cy, cx - ox)
        }
      guard axial > 0 else { continue }

      // Two tiers: a candidate whose center clears the origin's far EDGE is
      // squarely in the direction and always beats one that is merely
      // center-of-center offset — a display sitting almost directly above,
      // nudged a few points sideways, must not shadow a display genuinely
      // beside the origin. The center-offset tier remains as a fallback so
      // diagonal-only neighbors stay reachable.
      let clearsEdge: Bool =
        switch direction {
        case .right: cx > origin.frame.maxX
        case .left: cx < origin.frame.minX
        case .up: cy > origin.frame.maxY
        case .down: cy < origin.frame.minY
        }

      let score = axial + Self.perpendicularPenalty * abs(perpendicular)
      let beatsBest =
        best == nil
        || (clearsEdge && !best!.clearsEdge)
        || (clearsEdge == best!.clearsEdge && score < best!.score)
      if beatsBest {
        best = (candidate.uuid, clearsEdge, score)
      }
    }
    return best?.uuid
  }
}
