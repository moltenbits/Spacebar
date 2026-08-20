import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Fixture

private let windowID = 42
private let windowPID: pid_t = 4242
private let targetSpaceID: UInt64 = 3
private let targetFrame = CGRect(x: 1920, y: 25, width: 800, height: 600)
private let elsewhere = CGRect(x: 0, y: 25, width: 800, height: 600)

/// Records what the executor asked of AX and answers with scripted results.
private final class ScriptedAX {
  var trusted = true
  /// nil = no AX element; otherwise the write's reported success.
  var writeResult: Bool? = true
  var focusResult = true
  private(set) var writes: [(pid: pid_t, windowID: CGWindowID, origin: CGPoint)] = []
  private(set) var focusCalls: [(windowID: Int, pid: pid_t)] = []

  var hooks: DirectMoveAXHooks {
    DirectMoveAXHooks(
      isAccessibilityTrusted: { self.trusted },
      setPosition: { pid, windowID, origin in
        self.writes.append((pid, windowID, origin))
        return self.writeResult
      },
      activateAndVerifyFocus: { windowID, pid in
        self.focusCalls.append((windowID, pid))
        return self.focusResult
      })
  }
}

/// A manager whose CGS view of the window is fixed: `onTargetSpace` decides
/// membership, `frame` the WindowServer bounds (nil = window unknown to CGS).
private func makeManager(onTargetSpace: Bool, frame: CGRect?) -> (SpaceManager, ScriptedAX) {
  var ds = MockDataSource()
  if let frame {
    ds.windowList = [
      makeWindowDict(
        id: windowID, ownerName: "TestApp", pid: Int(windowPID),
        bounds: makeBoundsDict(
          x: frame.minX, y: frame.minY, width: frame.width, height: frame.height))
    ]
  }
  ds.windowSpaces = [windowID: onTargetSpace ? [targetSpaceID] : [1]]
  let manager = SpaceManager(dataSource: ds)
  let ax = ScriptedAX()
  manager.directMoveAXHooks = ax.hooks
  return (manager, ax)
}

private func request(activate: Bool = false, deadline: TimeInterval = 0.05)
  -> DirectWindowMoveRequest
{
  DirectWindowMoveRequest(
    windowID: windowID, pid: windowPID, targetSpaceID: targetSpaceID,
    targetFrame: targetFrame, activateAfterMove: activate, deadline: deadline)
}

// MARK: - Tests

@Suite("Direct Window Move Executor")
struct DirectWindowMoveExecutorTests {

  @Test(
    "Write accepted and CGS confirms Space + frame → moved; no focus work when activation is off")
  func movedWithoutActivation() throws {
    let (manager, ax) = makeManager(onTargetSpace: true, frame: targetFrame)

    let result = manager.performDirectWindowMove(request(deadline: 1.0))

    #expect(result == .moved(focused: nil, membershipVerified: true))
    let write = try #require(ax.writes.first)
    #expect(write.pid == windowPID)
    #expect(write.windowID == CGWindowID(windowID))
    #expect(write.origin == targetFrame.origin)
    #expect(ax.writes.count == 1)
    #expect(ax.focusCalls.isEmpty)
  }

  @Test("Activation requested → focus is verified after the move and its verdict returned")
  func activationVerdictReturned() throws {
    let (manager, ax) = makeManager(onTargetSpace: true, frame: targetFrame)
    ax.focusResult = false

    let result = manager.performDirectWindowMove(request(activate: true, deadline: 1.0))

    #expect(result == .moved(focused: false, membershipVerified: true))
    let focus = try #require(ax.focusCalls.first)
    #expect(focus.windowID == windowID)
    #expect(focus.pid == windowPID)
  }

  @Test("Window arrives clamped (oversized for the display) → moved, size change reported, no drag")
  func clampedSizeReported() {
    let clamped = CGRect(
      x: targetFrame.minX, y: targetFrame.minY, width: 500, height: 300)
    let (manager, _) = makeManager(onTargetSpace: true, frame: clamped)

    let result = manager.performDirectWindowMove(request(deadline: 1.0))

    #expect(result == .moved(focused: nil, membershipVerified: true, sizePreserved: false))
  }

  @Test("Write reported refused but the window reached the target Space → moved, never failed")
  func refusedWriteButMoved() {
    let (manager, ax) = makeManager(onTargetSpace: true, frame: targetFrame)
    ax.writeResult = false

    let result = manager.performDirectWindowMove(request(deadline: 1.0))

    #expect(result == .moved(focused: nil, membershipVerified: true))
  }

  @Test(
    "Write reported refused, membership lagging, frame at target → moved with membership unverified"
  )
  func refusedWriteFrameOnly() {
    let (manager, ax) = makeManager(onTargetSpace: false, frame: targetFrame)
    ax.writeResult = false

    let result = manager.performDirectWindowMove(request())

    #expect(result == .moved(focused: nil, membershipVerified: false))
  }

  @Test(
    "Write refused and nothing moved by the deadline → failed naming the refusal; no focus work")
  func refusedWriteNothingMoved() throws {
    let (manager, ax) = makeManager(onTargetSpace: false, frame: elsewhere)
    ax.writeResult = false

    let result = manager.performDirectWindowMove(request(activate: true))

    guard case .failed(let reason) = result else {
      Issue.record("expected .failed, got \(result)")
      return
    }
    #expect(reason.hasPrefix("ax-set-position-refused"))
    #expect(ax.focusCalls.isEmpty)
  }

  @Test("Write accepted but nothing moved by the deadline → failed with verify-timeout")
  func acceptedWriteNothingMoved() {
    let (manager, _) = makeManager(onTargetSpace: false, frame: elsewhere)

    let result = manager.performDirectWindowMove(request())

    guard case .failed(let reason) = result else {
      Issue.record("expected .failed, got \(result)")
      return
    }
    #expect(reason.hasPrefix("verify-timeout"))
  }

  @Test("No AX element → failed immediately, nothing to verify")
  func noElement() {
    let (manager, ax) = makeManager(onTargetSpace: false, frame: elsewhere)
    ax.writeResult = nil
    let start = Date()

    let result = manager.performDirectWindowMove(request(deadline: 2.0))

    #expect(result == .failed(reason: "ax-element-not-found"))
    #expect(Date().timeIntervalSince(start) < 1.0)
  }

  @Test("Accessibility not trusted → failed before any write")
  func untrusted() {
    let (manager, ax) = makeManager(onTargetSpace: true, frame: targetFrame)
    ax.trusted = false

    let result = manager.performDirectWindowMove(request())

    #expect(result == .failed(reason: "ax-not-trusted"))
    #expect(ax.writes.isEmpty)
  }
}
