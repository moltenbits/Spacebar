import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Helpers

private func window(
  _ id: Int, pid: Int, app: String = "App", spaces: [UInt64]
) -> WindowInfo {
  WindowInfo(
    id: id, ownerName: app, name: "Window \(id)", pid: pid,
    bounds: .zero, spaceIDs: spaces)
}

// MARK: - Space Close Window Planner

@Suite("Space Close Window Planner")
struct SpaceCloseWindowPlannerTests {

  @Test("App living entirely on the doomed space is quit, not closed window-by-window")
  func quitsAppFullyOnSpace() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [
        window(1, pid: 100, app: "IntelliJ IDEA", spaces: [5]),
        window(2, pid: 100, app: "IntelliJ IDEA", spaces: [5]),
      ], spaceID: 5)

    #expect(plan.actions == [.quitApp(pid: 100)])
    #expect(plan.expectedClosedWindowIDs == [1, 2])
  }

  @Test("App with a window on another space only loses its doomed-space window")
  func closesWindowWhenAppPresentElsewhere() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [
        window(1, pid: 100, spaces: [5]),
        window(2, pid: 100, spaces: [7]),
      ], spaceID: 5)

    #expect(plan.actions == [.closeWindow(windowID: 1, pid: 100)])
    #expect(plan.expectedClosedWindowIDs == [1])
  }

  @Test("Sticky window is never closed and produces no actions on its own")
  func stickyWindowLeftAlone() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [window(1, pid: 100, spaces: [5, 6])], spaceID: 5)

    #expect(plan.actions.isEmpty)
    #expect(plan.expectedClosedWindowIDs.isEmpty)
  }

  @Test("Sticky window counts as presence elsewhere for its app")
  func stickyWindowKeepsAppAlive() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [
        window(1, pid: 100, spaces: [5, 6]),
        window(2, pid: 100, spaces: [5]),
      ], spaceID: 5)

    #expect(plan.actions == [.closeWindow(windowID: 2, pid: 100)])
    #expect(plan.expectedClosedWindowIDs == [2])
  }

  @Test("Finder is closed window-by-window even when fully on the doomed space")
  func finderNeverQuit() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [window(1, pid: 100, app: "Finder", spaces: [5])], spaceID: 5)

    #expect(plan.actions == [.closeWindow(windowID: 1, pid: 100)])
  }

  @Test("Windows on other spaces produce no actions")
  func otherSpacesIgnored() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [
        window(1, pid: 100, spaces: [7]),
        window(2, pid: 200, spaces: [8]),
      ], spaceID: 5)

    #expect(plan.actions.isEmpty)
    #expect(plan.expectedClosedWindowIDs.isEmpty)
  }

  @Test("Empty window list produces an empty plan")
  func emptyWindowList() {
    let plan = SpaceCloseWindowPlanner.plan(windows: [], spaceID: 5)

    #expect(plan.actions.isEmpty)
    #expect(plan.expectedClosedWindowIDs.isEmpty)
  }

  @Test("Window with no space mapping is not treated as on the space")
  func unmappedWindowIgnored() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [window(1, pid: 100, spaces: [])], spaceID: 5)

    #expect(plan.actions.isEmpty)
  }

  @Test("Mixed apps emit one action group per app in enumeration order")
  func mixedAppsOrdering() {
    let plan = SpaceCloseWindowPlanner.plan(
      windows: [
        window(1, pid: 100, app: "IntelliJ IDEA", spaces: [5]),
        window(2, pid: 200, app: "Safari", spaces: [5]),
        window(3, pid: 100, app: "IntelliJ IDEA", spaces: [5]),
        window(4, pid: 200, app: "Safari", spaces: [9]),
      ], spaceID: 5)

    #expect(plan.actions == [.quitApp(pid: 100), .closeWindow(windowID: 2, pid: 200)])
    #expect(plan.expectedClosedWindowIDs == [1, 3, 2])
  }
}

// MARK: - Window Close Wait State

@Suite("Window Close Wait State")
struct WindowCloseWaitStateTests {

  @Test("Empty state is settled")
  func emptySettled() {
    #expect(WindowCloseWaitState().allSettled(isRunning: { _ in true }))
  }

  @Test("A pending window blocks settling until its close attempt resolves")
  func pendingWindowBlocks() {
    let state = WindowCloseWaitState()
    state.expectWindow(42)
    #expect(!state.allSettled(isRunning: { _ in false }))

    state.resolveWindow(42, closed: true)
    #expect(state.allSettled(isRunning: { _ in false }))
  }

  @Test("A failed close resolves the wait but is reported as a leftover")
  func failedCloseResolvesButReports() {
    let state = WindowCloseWaitState()
    state.expectWindow(42)
    state.resolveWindow(42, closed: false)

    #expect(state.allSettled(isRunning: { _ in false }))
    #expect(state.unsettledSummary(isRunning: { _ in false }) == "window-42-close-failed")
  }

  @Test("A quit target blocks settling only while its process runs")
  func quitBlocksWhileRunning() {
    let state = WindowCloseWaitState()
    state.expectQuit(pid: 7)

    #expect(!state.allSettled(isRunning: { _ in true }))
    #expect(state.allSettled(isRunning: { _ in false }))
  }

  @Test("Leftover summary names unconfirmed windows and still-running pids")
  func summaryNamesLeftovers() {
    let state = WindowCloseWaitState()
    state.expectWindow(2)
    state.expectQuit(pid: 7)
    state.expectQuit(pid: 9)

    let summary = state.unsettledSummary(isRunning: { $0 == 9 })
    #expect(summary == "window-2-unconfirmed,pid-9-still-running")
  }
}

// MARK: - Close Space With Windows

private final class MockSpaceNameStore: SpaceNameStoring {
  var names: [String: String] = [:]

  func customName(forSpaceUUID uuid: String) -> String? { names[uuid] }
  func setCustomName(_ name: String?, forSpaceUUID uuid: String) {
    names[uuid] = name
  }
  func allCustomNames() -> [String: String] { names }
  func pruneStaleNames(currentSpaces: [SpaceInfo]) {}
  func resolveSpaceID(_ input: String, spaces: [SpaceInfo]) -> UInt64? { nil }
}

@Suite("Close Space With Windows")
struct CloseSpaceWithWindowsTests {

  /// One display, two desktop spaces (10 current, 11 doomed).
  private func twoSpaceDataSource() -> MockDataSource {
    var ds = MockDataSource()
    ds.displaySpaces = [
      [
        "Display Identifier": "display-1",
        "Spaces": [
          ["ManagedSpaceID": 10, "uuid": "uuid-10", "type": 0],
          ["ManagedSpaceID": 11, "uuid": "uuid-11", "type": 0],
        ],
        "Current Space": ["ManagedSpaceID": 10],
      ]
    ]
    return ds
  }

  @Test("Closing the last desktop space fails before any window is touched")
  func lastSpaceGuardRunsFirst() {
    var ds = MockDataSource()
    ds.displaySpaces = [
      [
        "Display Identifier": "display-1",
        "Spaces": [["ManagedSpaceID": 10, "uuid": "uuid-10", "type": 0]],
        "Current Space": ["ManagedSpaceID": 10],
      ]
    ]
    let manager = SpaceManager(dataSource: ds)

    var result: Result<Void, SpaceCloseError>?
    manager.closeSpaceWithWindowsAndRemoveName(
      id: 10, spaceNameStore: MockSpaceNameStore()
    ) { result = $0 }

    guard case .failure(.cannotCloseLastSpace) = result else {
      Issue.record("expected .cannotCloseLastSpace, got \(String(describing: result))")
      return
    }
  }

  @Test("Closing an unknown space fails before any window is touched")
  func unknownSpaceGuardRunsFirst() {
    let manager = SpaceManager(dataSource: twoSpaceDataSource())

    var result: Result<Void, SpaceCloseError>?
    manager.closeSpaceWithWindowsAndRemoveName(
      id: 99, spaceNameStore: MockSpaceNameStore()
    ) { result = $0 }

    guard case .failure(.spaceNotFound) = result else {
      Issue.record("expected .spaceNotFound, got \(String(describing: result))")
      return
    }
  }

  @Test("closeWindowsInSpace completes immediately when the space holds no windows")
  func noWindowsCompletesImmediately() {
    let manager = SpaceManager(dataSource: twoSpaceDataSource())

    var completed = false
    manager.closeWindowsInSpace(id: 11) { completed = true }

    #expect(completed)
  }

  @Test("closeWindowsInSpace completes when the quit target's process is already gone")
  func quitTargetAlreadyGoneCompletes() async {
    var ds = twoSpaceDataSource()
    // A quit-eligible app on the doomed space with an invalid pid: the
    // terminate is a no-op and the process check reports it gone, so the
    // wait settles immediately instead of running out the timeout.
    ds.windowList = [makeWindowDict(id: 42, ownerName: "Stuck App", pid: -1)]
    ds.windowSpaces = [42: [11]]
    let manager = SpaceManager(dataSource: ds)

    await withCheckedContinuation { continuation in
      manager.closeWindowsInSpace(id: 11, timeout: 0.3) {
        continuation.resume()
      }
    }
  }
}
