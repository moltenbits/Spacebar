import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Window Move Executor

/// The two ways `SpaceManager.moveWindowToSpace` can relocate a window, behind
/// one seam so routing and fallback are testable without AX or Mission Control.
/// `SpaceManager` is the production executor; tests inject a recorder through
/// `SpaceManager.windowMoveExecutorOverride`.
protocol WindowMoveExecuting: AnyObject {
  /// Direct AX frame write + CGS verification. Returns `.failed` only while the
  /// window has not provably moved, so the caller may still run the drag.
  func performDirectWindowMove(_ request: DirectWindowMoveRequest) -> DirectWindowMoveResult

  /// Activate → Mission Control drag → re-activate (or restore the user's Space).
  func performMissionControlWindowMove(_ request: MissionControlWindowMoveRequest) throws -> Bool
}

struct DirectWindowMoveRequest: Equatable {
  let windowID: Int
  let pid: pid_t
  let targetSpaceID: UInt64
  /// Planned frame in global CG coordinates; its size is the window's current size.
  let targetFrame: CGRect
  let activateAfterMove: Bool
  /// Total budget shared by the write, verification, stability hold and race-guard read.
  let deadline: TimeInterval
}

enum DirectWindowMoveResult: Equatable {
  /// The window moved. `focused` is nil when activation was not requested,
  /// otherwise whether the moved window verified as the window a Cmd+Shift+D
  /// resize would target. `membershipVerified` is false when only the
  /// WindowServer frame proved the move (CGS membership still lagging at the
  /// deadline).
  case moved(focused: Bool?, membershipVerified: Bool = true)
  /// The window did not provably move; `reason` is a diagnostics token.
  case failed(reason: String)
}

struct MissionControlWindowMoveRequest: Equatable {
  let windowID: Int
  let windowTitle: String
  let targetSpaceID: UInt64
  let activateAfterMove: Bool
}

// MARK: - Direct Move AX Hooks

/// The live Accessibility primitives `performDirectWindowMove` depends on,
/// injectable so the executor's decisions (verify after any write attempt,
/// never report failure once the window moved, focus only after the move) are
/// unit-tested against scripted AX behaviour.
struct DirectMoveAXHooks {
  var isAccessibilityTrusted: () -> Bool
  /// Writes the window's AX position. Returns nil when no AX element could be
  /// resolved for the window (nothing was written), otherwise the AX write's
  /// reported success — which is NOT proof the write didn't take effect.
  var setPosition: (_ pid: pid_t, _ windowID: CGWindowID, _ origin: CGPoint) -> Bool?
  /// Activates the window and verifies it is what a Cmd+Shift+D resize would
  /// target. Returns whether focus verified.
  var activateAndVerifyFocus: (_ windowID: Int, _ pid: pid_t) -> Bool
}
