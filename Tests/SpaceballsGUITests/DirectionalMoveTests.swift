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
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    markSpace(vm, id: 1)
    vm.moveMarkedSpace(inDirection: .right)
    #expect(displayHosting(vm, spaceID: 1) == "display-right")

    vm.moveMarkedSpace(inDirection: .left)
    #expect(displayHosting(vm, spaceID: 1) == "display-left")
  }

  @Test("A direction with no physical neighbor is a no-op")
  func noNeighborIsNoOp() {
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    markSpace(vm, id: 1)
    vm.moveMarkedSpace(inDirection: .up)
    #expect(displayHosting(vm, spaceID: 1) == "display-left")
    vm.moveMarkedSpace(inDirection: .left)
    #expect(displayHosting(vm, spaceID: 1) == "display-left")
  }

  @Test("Without an arrangement, directions fall back to cycling")
  func fallbackToCycling() {
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
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
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .right)
    #expect(displayHosting(vm, windowID: 10) == "display-right")

    vm.moveMarkedWindow(inDirection: .left)
    #expect(displayHosting(vm, windowID: 10) == "display-left")
  }

  @Test("A direction with no physical neighbor is a no-op")
  func noNeighborIsNoOp() {
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.displayArrangement = sideBySideArrangement()
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .down)
    #expect(displayHosting(vm, windowID: 10) == "display-left")
  }

  @Test("Without an arrangement, directions fall back to cycling")
  func fallbackToCycling() {
    let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
    vm.refresh()

    vm.selectedItem = .windowRow(10)
    vm.toggleMoveMode()
    vm.moveMarkedWindow(inDirection: .up)
    #expect(displayHosting(vm, windowID: 10) == "display-right")
  }
}
