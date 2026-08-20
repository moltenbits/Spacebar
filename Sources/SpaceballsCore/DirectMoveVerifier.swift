import CoreGraphics
import Foundation

// MARK: - Direct Move Verification

/// How a direct (AX frame write) window move was confirmed to have taken effect.
/// Every case except `.failed` means the window moved — the caller must not
/// fall back to a Mission Control drag for any of them.
enum DirectMoveVerification: Equatable {
  /// CGS reports the target Space and the WindowServer origin matches the
  /// plan, both held for the stability window. The normal outcome.
  case verified
  /// The deadline passed without a stable hold, but the final fresh read shows
  /// the window on the target Space (frame still settling, or the app clamped it).
  case membershipLate
  /// The deadline passed with CGS still not publishing the target Space, but
  /// the WindowServer origin is at the planned position on the target display —
  /// the window has physically relocated; membership is lagging.
  case frameOnly
  /// Neither the Space nor the origin reached the target before the deadline.
  case failed(lastOnTarget: Bool, lastFrame: CGRect?)

  /// Whether the window provably moved (anything but `.failed`).
  var moved: Bool {
    if case .failed = self { return false }
    return true
  }
}

/// Waits for a direct window move to take effect. Pure apart from the
/// injected readers and clock, so the deadline / race-guard decisions are
/// unit-tested; `SpaceManager.performDirectWindowMove` supplies the real
/// CGS readers and the wall clock.
enum DirectMoveVerifier {

  static let positionTolerance: CGFloat = 2
  static let sizeTolerance: CGFloat = 5

  /// Polls `isOnTargetSpace` and `currentFrame` every `pollInterval` until
  /// membership and the frame's origin have agreed with the plan continuously
  /// for `stableDuration` (`.verified`), or `deadline` passes. At the deadline
  /// one fresh read of both decides: on the target Space → `.membershipLate`;
  /// origin at target → `.frameOnly`; otherwise `.failed`. A drift off target during the hold
  /// resets the stability timer (some apps report the target at once and keep
  /// animating).
  static func verify(
    targetFrame: CGRect,
    deadline: Date,
    stableDuration: TimeInterval = 0.06,
    pollInterval: TimeInterval = 0.025,
    now: () -> Date = { Date() },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    isOnTargetSpace: () -> Bool,
    currentFrame: () -> CGRect?
  ) -> DirectMoveVerification {
    var firstAtTarget: Date?
    while now() < deadline {
      let onTarget = isOnTargetSpace()
      let atFrame = currentFrame().map { originMatches($0, targetFrame) } ?? false
      if onTarget && atFrame {
        let since = firstAtTarget ?? now()
        firstAtTarget = since
        if now().timeIntervalSince(since) >= stableDuration {
          return .verified
        }
      } else {
        firstAtTarget = nil
      }
      // Never overshoot the deadline by a whole poll — it is a shared budget.
      // The last sleep is trimmed to the deadline and followed directly by the
      // final read below.
      let remaining = deadline.timeIntervalSince(now())
      if remaining <= pollInterval {
        sleep(max(remaining, 0))
        break
      }
      sleep(pollInterval)
    }

    // Race guard: membership and frame can land right at the deadline, and
    // CGS can publish membership after WindowServer has already relocated the
    // frame. Either one proves the move — dragging a moved window would be
    // the bug.
    let onTarget = isOnTargetSpace()
    let frame = currentFrame()
    if onTarget { return .membershipLate }
    if let frame, originMatches(frame, targetFrame) { return .frameOnly }
    return .failed(lastOnTarget: onTarget, lastFrame: frame)
  }

  /// Whether a WindowServer-reported frame's origin is "at" the planned
  /// origin (within 2pt). The move decision deliberately ignores size: AppKit
  /// clamps a window that is larger than its new display, and some apps settle
  /// their size separately — neither changes the fact that the window
  /// relocated, and origin-on-the-target-display is what proves that.
  static func originMatches(_ actual: CGRect, _ target: CGRect) -> Bool {
    abs(actual.minX - target.minX) < positionTolerance
      && abs(actual.minY - target.minY) < positionTolerance
  }

  /// Whether the size survived the move (within 5pt). Diagnostics only — the
  /// direct path never writes size, so a change here means the app or AppKit
  /// clamped it (typically an oversized window on a smaller display).
  static func sizePreserved(_ actual: CGRect, _ target: CGRect) -> Bool {
    abs(actual.width - target.width) < sizeTolerance
      && abs(actual.height - target.height) < sizeTolerance
  }
}
