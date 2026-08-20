import CoreGraphics
import Foundation

// MARK: - Window Move Route

/// How `SpaceManager.moveWindowToSpace` should relocate a window. Produced by
/// `WindowMovePlanner.route` from a `getAllSpaces()` snapshot plus the window's
/// CGS facts, and consumed before any Mission Control work begins.
public enum WindowMoveRoute: Equatable {
  /// The window's Space and the target Space are both visible right now (each
  /// is current on a different display), so the window can be relocated with a
  /// plain AX position write to `targetFrame` — the same mechanism the resize
  /// grid uses to cycle a window between displays. WindowServer reassigns a
  /// window to the Space shown on whichever display its frame lands on, exactly
  /// as it does for a manual cross-display drag. Size is preserved exactly.
  case direct(targetFrame: CGRect)
  /// The Mission Control drag is required, or the direct path is not provably
  /// safe for this window. `reason` is a stable diagnostics token.
  case missionControl(reason: DeclineReason)

  /// Why the direct path was declined. Stable tokens for the diagnostics log.
  public enum DeclineReason: Equatable, CustomStringConvertible {
    case targetNotFound
    case targetNotDesktop
    case targetNotCurrent
    case windowAlreadyOnTarget
    case stickyWindow
    case sourceUnknown
    case sourceNotFound
    case sourceNotDesktop
    case sourceNotCurrent
    case sameDisplay
    case windowOffscreen
    case boundsUnknown
    case displayFrameUnknown(displayUUID: String)

    public var description: String {
      switch self {
      case .targetNotFound: return "target-not-found"
      case .targetNotDesktop: return "target-not-desktop"
      case .targetNotCurrent: return "target-not-current"
      case .windowAlreadyOnTarget: return "window-already-on-target"
      case .stickyWindow: return "sticky-window"
      case .sourceUnknown: return "source-unknown"
      case .sourceNotFound: return "source-not-found"
      case .sourceNotDesktop: return "source-not-desktop"
      case .sourceNotCurrent: return "source-not-current"
      case .sameDisplay: return "same-display"
      case .windowOffscreen: return "window-offscreen"
      case .boundsUnknown: return "bounds-unknown"
      case .displayFrameUnknown(let uuid): return "display-frame-unknown:\(uuid)"
      }
    }
  }
}

// MARK: - Planner

/// Decides whether a window move can skip Mission Control. Pure: no AX, no
/// NSScreen — callers supply the CGS snapshot and display geometry.
public enum WindowMovePlanner {

  /// - Parameters:
  ///   - spaces: `getAllSpaces()` snapshot.
  ///   - windowSpaceIDs: `fetchSpacesForWindow` for the window being moved.
  ///   - targetSpaceID: destination Space.
  ///   - windowBounds: the window's frame in global CG coordinates (top-left
  ///     origin), or nil when CGS has no record of it.
  ///   - windowIsOnscreen: `kCGWindowIsOnscreen`. A window can map to the
  ///     current Space while minimized or hidden by Stage Manager; those keep
  ///     the Mission Control path until the direct write is proven for them.
  ///   - displayVisibleFrames: each display's visible area (menu bar and Dock
  ///     excluded) in global CG coordinates, keyed by CGS display UUID.
  public static func route(
    spaces: [SpaceInfo],
    windowSpaceIDs: [UInt64],
    targetSpaceID: UInt64,
    windowBounds: CGRect?,
    windowIsOnscreen: Bool,
    displayVisibleFrames: [String: CGRect]
  ) -> WindowMoveRoute {
    guard let target = spaces.first(where: { $0.id == targetSpaceID }) else {
      return .missionControl(reason: .targetNotFound)
    }
    guard target.type == .desktop else {
      return .missionControl(reason: .targetNotDesktop)
    }
    guard target.isCurrent else {
      return .missionControl(reason: .targetNotCurrent)
    }

    guard !windowSpaceIDs.contains(targetSpaceID) else {
      return .missionControl(reason: .windowAlreadyOnTarget)
    }
    // A sticky window ("Assign to All Desktops") is on every Space already;
    // membership verification would pass before anything moved.
    guard windowSpaceIDs.count <= 1 else {
      return .missionControl(reason: .stickyWindow)
    }
    guard let sourceSpaceID = windowSpaceIDs.first else {
      return .missionControl(reason: .sourceUnknown)
    }
    guard let source = spaces.first(where: { $0.id == sourceSpaceID }) else {
      return .missionControl(reason: .sourceNotFound)
    }
    guard source.type == .desktop else {
      return .missionControl(reason: .sourceNotDesktop)
    }
    guard source.isCurrent else {
      return .missionControl(reason: .sourceNotCurrent)
    }
    // Two current Spaces on one display never happens with a sane snapshot,
    // but a same-display move is never a direct one — decline rather than write.
    guard source.displayUUID != target.displayUUID else {
      return .missionControl(reason: .sameDisplay)
    }

    guard windowIsOnscreen else {
      return .missionControl(reason: .windowOffscreen)
    }
    guard let bounds = windowBounds else {
      return .missionControl(reason: .boundsUnknown)
    }
    guard let sourceFrame = displayVisibleFrames[source.displayUUID] else {
      return .missionControl(reason: .displayFrameUnknown(displayUUID: source.displayUUID))
    }
    guard let targetFrame = displayVisibleFrames[target.displayUUID] else {
      return .missionControl(reason: .displayFrameUnknown(displayUUID: target.displayUUID))
    }

    return .direct(
      targetFrame: CGRect(
        origin: mapOrigin(of: bounds, from: sourceFrame, to: targetFrame),
        size: bounds.size))
  }

  /// Maps a window's origin from one display's visible area to another's,
  /// preserving its *relative* placement: each axis is normalized over the
  /// display's movable range (visible extent minus window extent) so a window
  /// flush with the right/bottom edge stays flush after the move. Fractions are
  /// clamped to 0…1 for windows hanging off the source. An axis where the
  /// window is larger than the target's visible extent has no movable range and
  /// pins to the target's origin on that axis — the window is never shrunk.
  /// Origins are rounded to whole points.
  static func mapOrigin(of window: CGRect, from source: CGRect, to target: CGRect) -> CGPoint {
    func map(
      _ origin: CGFloat, _ extent: CGFloat, _ src: (min: CGFloat, size: CGFloat),
      _ dst: (min: CGFloat, size: CGFloat)
    ) -> CGFloat {
      let movableSource = max(src.size - extent, 0)
      let movableTarget = max(dst.size - extent, 0)
      let fraction = movableSource > 0 ? min(max((origin - src.min) / movableSource, 0), 1) : 0
      return (dst.min + fraction * movableTarget).rounded()
    }
    return CGPoint(
      x: map(window.minX, window.width, (source.minX, source.width), (target.minX, target.width)),
      y: map(window.minY, window.height, (source.minY, source.height), (target.minY, target.height))
    )
  }
}
