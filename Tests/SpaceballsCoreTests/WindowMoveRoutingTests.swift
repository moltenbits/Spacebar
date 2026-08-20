import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Recording executor

/// Stands in for both legs of a window move so routing, fallback, and the
/// "never drag after a successful direct move" rule can be asserted without
/// touching AX or Mission Control.
private final class RecordingExecutor: WindowMoveExecuting {
  var directResult: DirectWindowMoveResult = .moved(focused: true)
  var missionControlResult = true
  private(set) var directRequests: [DirectWindowMoveRequest] = []
  private(set) var missionControlRequests: [MissionControlWindowMoveRequest] = []
  private(set) var order: [String] = []

  func performDirectWindowMove(_ request: DirectWindowMoveRequest) -> DirectWindowMoveResult {
    directRequests.append(request)
    order.append("direct")
    return directResult
  }

  func performMissionControlWindowMove(_ request: MissionControlWindowMoveRequest) throws -> Bool {
    missionControlRequests.append(request)
    order.append("mission-control")
    return missionControlResult
  }
}

// MARK: - Fixture

private let windowID = 42
private let windowPID = 4242

/// Display A: Spaces 1 (current), 2 — Display B: Spaces 3 (current), 4.
private func makeDisplayDict(
  displayUUID: String, spaceIDs: [Int], currentSpaceID: Int
) -> [String: Any] {
  [
    "Display Identifier": displayUUID,
    "Spaces": spaceIDs.map { ["ManagedSpaceID": $0, "uuid": "uuid-\($0)", "type": 0] },
    "Current Space": ["ManagedSpaceID": currentSpaceID],
  ]
}

private let frames: [String: CGRect] = [
  "display-A": CGRect(x: 0, y: 25, width: 1920, height: 1055),
  "display-B": CGRect(x: 1920, y: 25, width: 1440, height: 815),
]

private func makeManager(
  windowSpaceIDs: [UInt64] = [1],
  isOnscreen: Bool = true
) -> (SpaceManager, RecordingExecutor) {
  var ds = MockDataSource()
  ds.displaySpaces = [
    makeDisplayDict(displayUUID: "display-A", spaceIDs: [1, 2], currentSpaceID: 1),
    makeDisplayDict(displayUUID: "display-B", spaceIDs: [3, 4], currentSpaceID: 3),
  ]
  ds.windowList = [
    makeWindowDict(
      id: windowID, ownerName: "TestApp", name: "Doc.txt", pid: windowPID,
      bounds: makeBoundsDict(x: 0, y: 25, width: 800, height: 600),
      isOnscreen: isOnscreen)
  ]
  ds.windowSpaces = [windowID: windowSpaceIDs]

  let manager = SpaceManager(dataSource: ds)
  let executor = RecordingExecutor()
  manager.windowMoveExecutorOverride = executor
  manager.displayVisibleFramesProvider = { frames }
  return (manager, executor)
}

// MARK: - Routing

@Suite("Window Move Routing")
struct WindowMoveRoutingTests {

  @Test("Both Spaces visible → direct leg only, with the planned frame and pid")
  func directWhenBothVisible() throws {
    let (manager, executor) = makeManager()

    let moved = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(moved)
    #expect(executor.order == ["direct"])
    let request = try #require(executor.directRequests.first)
    #expect(request.windowID == windowID)
    #expect(request.pid == pid_t(windowPID))
    #expect(request.targetSpaceID == 3)
    // Top-left-aligned on A → top-left-aligned on B, size preserved.
    #expect(request.targetFrame == CGRect(x: 1920, y: 25, width: 800, height: 600))
    #expect(request.activateAfterMove)
    #expect(request.deadline == manager.directMoveDeadline)
  }

  @Test("activateAfterMove=false is passed through to the direct leg")
  func noActivatePassedThrough() throws {
    let (manager, executor) = makeManager()

    _ = try manager.moveWindowToSpace(
      windowID: windowID, targetSpaceID: 3, activateAfterMove: false)

    #expect(executor.directRequests.first?.activateAfterMove == false)
  }

  @Test("Direct leg failure falls back to Mission Control, in that order")
  func directFailureFallsBack() throws {
    let (manager, executor) = makeManager()
    executor.directResult = .failed(reason: "ax-set-position-refused")

    let moved = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(moved)
    #expect(executor.order == ["direct", "mission-control"])
    let request = try #require(executor.missionControlRequests.first)
    #expect(request.windowID == windowID)
    #expect(request.windowTitle == "Doc.txt")
    #expect(request.targetSpaceID == 3)
    #expect(request.activateAfterMove)
  }

  @Test("Mission Control result is returned when the fallback runs")
  func fallbackResultReturned() throws {
    let (manager, executor) = makeManager()
    executor.directResult = .failed(reason: "verify-timeout")
    executor.missionControlResult = false

    #expect(try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3) == false)
  }

  @Test("A successful direct move never drags, even when focus verification failed")
  func noFallbackAfterDirectSuccess() throws {
    let (manager, executor) = makeManager()
    executor.directResult = .moved(focused: false)

    let moved = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(moved)
    #expect(executor.order == ["direct"])
  }

  @Test("A frame-only verified direct move (membership lagging) never drags either")
  func noFallbackAfterFrameOnlyVerification() throws {
    let (manager, executor) = makeManager()
    executor.directResult = .moved(focused: nil, membershipVerified: false)

    let moved = try manager.moveWindowToSpace(
      windowID: windowID, targetSpaceID: 3, activateAfterMove: false)

    #expect(moved)
    #expect(executor.order == ["direct"])
  }

  @Test("Target Space not visible → Mission Control only")
  func targetNotVisibleUsesMissionControl() throws {
    let (manager, executor) = makeManager()

    _ = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 4)

    #expect(executor.order == ["mission-control"])
  }

  @Test("Window's own Space not visible → Mission Control only")
  func sourceNotVisibleUsesMissionControl() throws {
    let (manager, executor) = makeManager(windowSpaceIDs: [2])

    _ = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(executor.order == ["mission-control"])
  }

  @Test("Same-display move → Mission Control only")
  func sameDisplayUsesMissionControl() throws {
    let (manager, executor) = makeManager()

    _ = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 2)

    #expect(executor.order == ["mission-control"])
  }

  @Test("Offscreen (minimized) window → Mission Control only")
  func offscreenUsesMissionControl() throws {
    let (manager, executor) = makeManager(isOnscreen: false)

    _ = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(executor.order == ["mission-control"])
  }

  @Test("Unknown display geometry → Mission Control only")
  func unknownGeometryUsesMissionControl() throws {
    let (manager, executor) = makeManager()
    manager.displayVisibleFramesProvider = { [:] }

    _ = try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 3)

    #expect(executor.order == ["mission-control"])
  }

  @Test("Unknown window throws before either leg runs")
  func unknownWindowThrows() throws {
    let (manager, executor) = makeManager()

    #expect(throws: WindowActivationError.windowNotFound(windowID: 999)) {
      try manager.moveWindowToSpace(windowID: 999, targetSpaceID: 3)
    }
    #expect(executor.order.isEmpty)
  }

  @Test("Unknown target Space returns false before either leg runs")
  func unknownTargetReturnsFalse() throws {
    let (manager, executor) = makeManager()

    #expect(try manager.moveWindowToSpace(windowID: windowID, targetSpaceID: 999) == false)
    #expect(executor.order.isEmpty)
  }
}
