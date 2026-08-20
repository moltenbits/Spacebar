import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Fake clock

/// Deterministic clock: time advances only when the verifier sleeps.
private final class FakeClock {
  private(set) var elapsed: TimeInterval = 0
  func now() -> Date { Date(timeIntervalSinceReferenceDate: elapsed) }
  func sleep(_ interval: TimeInterval) { elapsed += interval }
}

private let target = CGRect(x: 1920, y: 25, width: 800, height: 600)
private let elsewhere = CGRect(x: 100, y: 100, width: 800, height: 600)

/// Runs the verifier with a 1s deadline. `onTarget` / `frame` are called once
/// per poll (and once more for the deadline read) with the fake clock, so
/// sequences can be expressed in terms of elapsed time.
private func verify(
  clock: FakeClock = FakeClock(),
  deadline: TimeInterval = 1.0,
  onTarget: @escaping (TimeInterval) -> Bool,
  frame: @escaping (TimeInterval) -> CGRect?
) -> (DirectMoveVerification, FakeClock) {
  let result = DirectMoveVerifier.verify(
    targetFrame: target,
    deadline: Date(timeIntervalSinceReferenceDate: deadline),
    now: clock.now, sleep: clock.sleep,
    isOnTargetSpace: { onTarget(clock.elapsed) },
    currentFrame: { frame(clock.elapsed) })
  return (result, clock)
}

// MARK: - Tests

@Suite("Direct Move Verifier")
struct DirectMoveVerifierTests {

  @Test("Membership and frame stable for the hold window → verified well before the deadline")
  func verifiedEarly() {
    let (result, clock) = verify(onTarget: { _ in true }, frame: { _ in target })
    #expect(result == .verified)
    #expect(result.moved)
    // 60ms hold at 25ms polls: 0, 25, 50, 75 → verified at 75ms.
    #expect(clock.elapsed < 0.1)
  }

  @Test("Frame at target but membership never published → frameOnly (moved, no fallback)")
  func frameOnlyAtDeadline() {
    let (result, clock) = verify(onTarget: { _ in false }, frame: { _ in target })
    #expect(result == .frameOnly)
    #expect(result.moved)
    #expect(clock.elapsed >= 0.99)
  }

  @Test("Membership published but frame never matches → membershipLate (moved, no fallback)")
  func membershipOnlyAtDeadline() {
    let (result, _) = verify(onTarget: { _ in true }, frame: { _ in elsewhere })
    #expect(result == .membershipLate)
    #expect(result.moved)
  }

  @Test("Membership published but frame unreadable → membershipLate")
  func membershipWithUnreadableFrame() {
    let (result, _) = verify(onTarget: { _ in true }, frame: { _ in nil })
    #expect(result == .membershipLate)
  }

  @Test("Membership that lands exactly at the deadline is caught by the final read")
  func membershipLandsAtDeadline() {
    let (result, _) = verify(onTarget: { $0 >= 0.99 }, frame: { _ in elsewhere })
    #expect(result == .membershipLate)
  }

  @Test("Frame that lands exactly at the deadline is caught by the final read")
  func frameLandsAtDeadline() {
    let (result, _) = verify(onTarget: { _ in false }, frame: { $0 >= 0.99 ? target : elsewhere })
    #expect(result == .frameOnly)
  }

  @Test("Neither signal reaches the target → failed, carrying the last reads")
  func neitherFails() {
    let (result, _) = verify(onTarget: { _ in false }, frame: { _ in elsewhere })
    #expect(result == .failed(lastOnTarget: false, lastFrame: elsewhere))
    #expect(!result.moved)
  }

  @Test("Nothing readable at all → failed with nil frame")
  func nothingReadableFails() {
    let (result, _) = verify(onTarget: { _ in false }, frame: { _ in nil })
    #expect(result == .failed(lastOnTarget: false, lastFrame: nil))
  }

  @Test("A drift off target resets the stability hold")
  func driftResetsHold() {
    // On target from the start, drifts away between 30ms and 60ms, then settles.
    let (result, clock) = verify(
      onTarget: { _ in true },
      frame: { t in (0.03...0.06).contains(t) ? elsewhere : target })
    #expect(result == .verified)
    // Without the drift it verifies at 75ms; the reset pushes it past 60ms + hold.
    #expect(clock.elapsed > 0.1)
  }

  @Test("Oversized window whose size the app clamps still verifies early (origin decides)")
  func clampedSizeVerifiesEarly() {
    let clamped = CGRect(x: target.minX, y: target.minY, width: 500, height: 300)
    let (result, clock) = verify(onTarget: { _ in true }, frame: { _ in clamped })
    #expect(result == .verified)
    #expect(clock.elapsed < 0.1)
  }

  @Test("Late but stable arrival verifies before the deadline")
  func lateArrivalVerifies() {
    let (result, clock) = verify(onTarget: { $0 >= 0.5 }, frame: { $0 >= 0.5 ? target : elsewhere })
    #expect(result == .verified)
    #expect(clock.elapsed > 0.5 && clock.elapsed < 1.0)
  }
}

// MARK: - Frame tolerance

@Suite("Direct Move Verifier — frame tolerance")
struct DirectMoveFrameToleranceTests {

  @Test("Exact frame matches origin and preserves size")
  func exact() {
    #expect(DirectMoveVerifier.originMatches(target, target))
    #expect(DirectMoveVerifier.sizePreserved(target, target))
  }

  @Test("Sub-tolerance drift in origin and size still matches")
  func withinTolerance() {
    let actual = CGRect(x: 1921, y: 26, width: 803, height: 597)
    #expect(DirectMoveVerifier.originMatches(actual, target))
    #expect(DirectMoveVerifier.sizePreserved(actual, target))
  }

  @Test("Origin off by more than the tolerance does not match")
  func originOff() {
    let actual = CGRect(x: 1925, y: 25, width: 800, height: 600)
    #expect(!DirectMoveVerifier.originMatches(actual, target))
  }

  @Test("A size change (app clamped an oversized window) is reported but does not deny the move")
  func sizeChangedStillMatchesOrigin() {
    let actual = CGRect(x: 1920, y: 25, width: 800, height: 590)
    #expect(DirectMoveVerifier.originMatches(actual, target))
    #expect(!DirectMoveVerifier.sizePreserved(actual, target))
  }
}
