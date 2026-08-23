import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore
@testable import SpaceballsGUILib

// MARK: - Helpers (local to this suite)

private func makeBounds(x: Double, y: Double, width: Double, height: Double) -> CFDictionary {
  CGRectCreateDictionaryRepresentation(CGRect(x: x, y: y, width: width, height: height))
}

private func space(id: Int, uuid: String, type: Int = 0) -> [String: Any] {
  ["ManagedSpaceID": id, "uuid": uuid, "type": type]
}

private func display(uuid: String, spaces: [[String: Any]], current: Int) -> [String: Any] {
  [
    "Display Identifier": uuid,
    "Spaces": spaces,
    "Current Space": ["ManagedSpaceID": current],
  ]
}

private func window(id: Int, owner: String, name: String, pid: Int) -> [String: Any] {
  [
    "kCGWindowNumber": id,
    "kCGWindowOwnerName": owner,
    "kCGWindowName": name,
    "kCGWindowOwnerPID": pid,
    "kCGWindowLayer": 0,
    "kCGWindowBounds": makeBounds(x: 0, y: 0, width: 800, height: 600),
    "kCGWindowIsOnscreen": true,
  ]
}

/// display-left (space 1, window 10) and display-right (space 3, window 30),
/// physically side by side.
private func makeTwoDisplayScenario() -> MutableMockDataSource {
  let ds = MutableMockDataSource()
  ds.displaySpaces = [
    display(uuid: "display-left", spaces: [space(id: 1, uuid: "uuid-1")], current: 1),
    display(uuid: "display-right", spaces: [space(id: 3, uuid: "uuid-3")], current: 3),
  ]
  ds.windowList = [
    window(id: 10, owner: "Safari", name: "Google", pid: 100),
    window(id: 30, owner: "Code", name: "main.swift", pid: 300),
  ]
  ds.windowSpaces = [10: [1], 30: [3]]
  return ds
}

private func sideBySideArrangement() -> DisplayArrangement {
  DisplayArrangement(displays: [
    .init(uuid: "display-left", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
    .init(uuid: "display-right", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
  ])
}

private func markSpace(_ vm: SwitcherViewModel, id: UInt64) {
  vm.selectedItem = .spaceHeader(id)
  vm.toggleSpaceMoveMode()
}

private func displayHosting(_ vm: SwitcherViewModel, spaceID: UInt64) -> String? {
  vm.sections.first(where: { $0.id == spaceID })?.displayUUID
}

private func displayHosting(_ vm: SwitcherViewModel, windowID: Int) -> String? {
  vm.sections.first(where: { $0.windows.contains(where: { $0.id == windowID }) })?
    .displayUUID
}

@Suite("Directional Space Move")
struct DirectionalSpaceMoveTests {

  @Test("Moving toward a physical neighbor retargets the marked space")
  func directionalRetarget() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    markSpace(vm, id: 1)
    vm.moveMarkedSpace(inDirection: .right)
    #expect(displayHosting(vm, spaceID: 1) == "display-right")

    vm.moveMarkedSpace(inDirection: .left)
    #expect(displayHosting(vm, spaceID: 1) == "display-left")
  }

  @Test("An axis with no displays on it is a no-op")
  func emptyAxisIsNoOp() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    markSpace(vm, id: 1)
    vm.moveMarkedSpace(inDirection: .up)
    #expect(displayHosting(vm, spaceID: 1) == "display-left")
  }

  @Test("Past the far edge, the move wraps to the opposite end")
  func moveWrapsAtTheEdge() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    markSpace(vm, id: 1)
    vm.moveMarkedSpace(inDirection: .left)
    #expect(displayHosting(vm, spaceID: 1) == "display-right")
  }

  @Test("Without an arrangement, directions fall back to cycling")
  func fallbackToCycling() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.refresh()

    markSpace(vm, id: 1)
    // .up has no directional meaning here — it cycles backward, and with two
    // displays wraps onto the other one.
    vm.moveMarkedSpace(inDirection: .up)
    #expect(displayHosting(vm, spaceID: 1) == "display-right")
  }
}

@Suite("Directional Window Move")
struct DirectionalWindowMoveTests {

  @Test("Moving toward a physical neighbor relocates the marked window row")
  func directionalRetarget() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .right)
    #expect(displayHosting(vm, windowID: 10) == "display-right")

    vm.moveMarkedWindow(inDirection: .left)
    #expect(displayHosting(vm, windowID: 10) == "display-left")
  }

  @Test("An axis with no displays on it is a no-op")
  func emptyAxisIsNoOp() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .down)
    #expect(displayHosting(vm, windowID: 10) == "display-left")
  }

  @Test("Past the far edge, the move wraps to the opposite end")
  func moveWrapsAtTheEdge() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .left)
    #expect(displayHosting(vm, windowID: 10) == "display-right")
  }

  @Test("Without an arrangement, directions fall back to cycling")
  func fallbackToCycling() {
    let vm = makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .up)
    #expect(displayHosting(vm, windowID: 10) == "display-right")
  }
}

// MARK: - Move-mode vertical space stepping

/// T-shaped layout: upper-left (space 1), upper-center (spaces 2, 3),
/// upper-right (space 4) side by side on top, with the primary display
/// (spaces 5, 6) below the upper-center one. `displayOrder` deliberately
/// places upper-right right after upper-center — the flat list's next group
/// is NOT the display physically below.
private func makeTShapeScenario() -> MutableMockDataSource {
  let ds = MutableMockDataSource()
  ds.displaySpaces = [
    display(uuid: "display-upper-left", spaces: [space(id: 1, uuid: "uuid-1")], current: 1),
    display(
      uuid: "display-upper-center",
      spaces: [space(id: 2, uuid: "uuid-2"), space(id: 3, uuid: "uuid-3")],
      current: 2),
    display(uuid: "display-upper-right", spaces: [space(id: 4, uuid: "uuid-4")], current: 4),
    display(
      uuid: "display-bottom",
      spaces: [space(id: 5, uuid: "uuid-5"), space(id: 6, uuid: "uuid-6")],
      current: 5),
  ]
  ds.windowList = [
    window(id: 10, owner: "A", name: "a", pid: 100),
    window(id: 20, owner: "B", name: "b", pid: 200),
    window(id: 30, owner: "C", name: "c", pid: 300),
    window(id: 40, owner: "D", name: "d", pid: 400),
    window(id: 50, owner: "E", name: "e", pid: 500),
    window(id: 60, owner: "F", name: "f", pid: 600),
  ]
  ds.windowSpaces = [10: [1], 20: [2], 30: [3], 40: [4], 50: [5], 60: [6]]
  return ds
}

private func tShapeArrangement() -> DisplayArrangement {
  DisplayArrangement(displays: [
    .init(uuid: "display-upper-left", frame: CGRect(x: 0, y: 1440, width: 1920, height: 1080)),
    .init(
      uuid: "display-upper-center", frame: CGRect(x: 1920, y: 1440, width: 1920, height: 1080)),
    .init(uuid: "display-upper-right", frame: CGRect(x: 3840, y: 1440, width: 1920, height: 1080)),
    .init(uuid: "display-bottom", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1440)),
  ])
}

private func makeTShapeViewModel() -> SwitcherViewModel {
  let vm = makeTestSwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTShapeScenario()))
  vm.displayArrangement = tShapeArrangement()
  vm.refresh()
  vm.displayOrder = [
    "display-upper-left", "display-upper-center", "display-upper-right", "display-bottom",
  ]
  return vm
}

private func markWindow(_ vm: SwitcherViewModel, id: Int) {
  vm.selectedItem = .windowRow(id)
  vm.toggleMoveMode()
}

private func spaceHosting(_ vm: SwitcherViewModel, windowID: Int) -> UInt64? {
  vm.sections.first(where: { $0.windows.contains(where: { $0.id == windowID }) })?.id
}

@Suite("Move-Mode Vertical Space Stepping")
struct MoveModeVerticalSteppingTests {

  @Test("Stepping down past the display's last space follows the arrangement")
  func downCrossesToArrangedDisplay() {
    let vm = makeTShapeViewModel()
    markWindow(vm, id: 30)  // space 3, last space of upper-center

    vm.moveMarkedWindowToNextSpace()

    // Physically below upper-center is the bottom display — NOT upper-right,
    // which is merely next in displayOrder / the flat list.
    #expect(displayHosting(vm, windowID: 30) == "display-bottom")
    #expect(spaceHosting(vm, windowID: 30) == 5)
  }

  @Test("Stepping up past the display's first space enters the display above at its last space")
  func upCrossesToArrangedDisplayLastSpace() {
    let vm = makeTShapeViewModel()
    markWindow(vm, id: 50)  // space 5, first space of the bottom display

    vm.moveMarkedWindowToPreviousSpace()

    #expect(displayHosting(vm, windowID: 50) == "display-upper-center")
    #expect(spaceHosting(vm, windowID: 50) == 3)
  }

  @Test("Stepping within a display stays linear")
  func withinDisplayStaysLinear() {
    let vm = makeTShapeViewModel()
    markWindow(vm, id: 20)  // space 2, first space of upper-center

    vm.moveMarkedWindowToNextSpace()

    #expect(spaceHosting(vm, windowID: 20) == 3)
  }

  @Test("Down past the bottom display wraps to the top of its column")
  func downFromBottomWrapsToTop() {
    let vm = makeTShapeViewModel()
    markWindow(vm, id: 60)  // space 6, last space of the bottom display

    vm.moveMarkedWindowToNextSpace()

    #expect(displayHosting(vm, windowID: 60) == "display-upper-center")
    #expect(spaceHosting(vm, windowID: 60) == 2)
  }

  @Test("No display on the vertical axis wraps within the display's own spaces")
  func noVerticalAxisWrapsWithinDisplay() {
    let ds = makeTwoDisplayScenario()
    // Give display-left a second space so the wrap is observable.
    ds.displaySpaces = [
      display(
        uuid: "display-left",
        spaces: [space(id: 1, uuid: "uuid-1"), space(id: 2, uuid: "uuid-2")],
        current: 1),
      display(uuid: "display-right", spaces: [space(id: 3, uuid: "uuid-3")], current: 3),
    ]
    ds.windowSpaces = [10: [1], 30: [3]]
    let vm = makeTestSwitcherViewModel(spaceManager: SpaceManager(dataSource: ds))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()
    vm.displayOrder = ["display-left", "display-right"]

    markWindow(vm, id: 10)  // space 1 of display-left
    vm.moveMarkedWindowToNextSpace()
    #expect(spaceHosting(vm, windowID: 10) == 2)

    // At the display's last space with nothing below: wrap back to its first
    // space instead of leaking into display-right.
    vm.moveMarkedWindowToNextSpace()
    #expect(spaceHosting(vm, windowID: 10) == 1)
  }

  @Test("Without display grouping (modes 1/2) the flat scan is unchanged")
  func flatScanKeptWithoutDisplayOrder() {
    let vm = makeTShapeViewModel()
    vm.displayOrder = []
    markWindow(vm, id: 30)

    vm.moveMarkedWindowToNextSpace()

    // Whatever section follows in the flat list — the point is it moved and
    // didn't require an arrangement decision.
    #expect(spaceHosting(vm, windowID: 30) != 3)
  }
}
