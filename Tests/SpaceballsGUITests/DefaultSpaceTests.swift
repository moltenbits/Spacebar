import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore
@testable import SpaceballsGUILib

// MARK: - Helpers (local to this suite)

private func desktop(id: UInt64, uuid: String, display: String, current: Bool = false) -> SpaceInfo
{
  SpaceInfo(id: id, uuid: uuid, type: .desktop, displayUUID: display, isCurrent: current)
}

@Suite("Default Space Naming")
struct DefaultSpaceNamerTests {

  @Test("A freshly connected external display's sole unnamed space is assigned")
  func freshExternalDisplayAssigned() {
    let spaces = [
      desktop(id: 1, uuid: "uuid-1", display: "builtin", current: true),
      desktop(id: 2, uuid: "uuid-2", display: "external", current: true),
    ]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin", existingNames: [:])
    #expect(assigned == ["uuid-2"])
  }

  @Test("The built-in display never receives a Default Space")
  func builtinDisplaySkipped() {
    let spaces = [desktop(id: 1, uuid: "uuid-1", display: "builtin", current: true)]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin", existingNames: [:])
    #expect(assigned.isEmpty)
  }

  @Test("A display with multiple desktop spaces is left alone")
  func multiSpaceDisplaySkipped() {
    let spaces = [
      desktop(id: 2, uuid: "uuid-2", display: "external", current: true),
      desktop(id: 3, uuid: "uuid-3", display: "external"),
    ]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin", existingNames: [:])
    #expect(assigned.isEmpty)
  }

  @Test("A sole space the user already named is left alone")
  func namedSoleSpaceSkipped() {
    let spaces = [desktop(id: 2, uuid: "uuid-2", display: "external", current: true)]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin", existingNames: ["uuid-2": "Work"])
    #expect(assigned.isEmpty)
  }

  @Test("Re-running the assignment is idempotent")
  func idempotentAssignment() {
    let spaces = [desktop(id: 2, uuid: "uuid-2", display: "external", current: true)]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin",
      existingNames: ["uuid-2": SpaceNameStore.defaultSpaceName])
    #expect(assigned.isEmpty)
  }

  @Test("Fullscreen spaces don't count against the sole-desktop rule")
  func fullscreenSpacesIgnored() {
    let spaces = [
      desktop(id: 2, uuid: "uuid-2", display: "external", current: true),
      SpaceInfo(
        id: 9, uuid: "uuid-9", type: .fullscreen, displayUUID: "external", isCurrent: false),
    ]
    let assigned = DefaultSpaceNamer.assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: "builtin", existingNames: [:])
    #expect(assigned == ["uuid-2"])
  }

  @Test("assignNames writes the Default Space name through the store")
  func assignNamesWritesThroughStore() {
    let store = MockSpaceNameStore()
    let spaces = [
      desktop(id: 1, uuid: "uuid-1", display: "builtin", current: true),
      desktop(id: 2, uuid: "uuid-2", display: "external", current: true),
    ]
    DefaultSpaceNamer.assignNames(spaces: spaces, builtinDisplayUUID: "builtin", store: store)
    #expect(store.customName(forSpaceUUID: "uuid-2") == SpaceNameStore.defaultSpaceName)
    #expect(store.customName(forSpaceUUID: "uuid-1") == nil)
  }
}

// MARK: - Space-move pinning

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

@Suite("Default Space Pinning")
struct DefaultSpacePinningTests {

  private func makeViewModel(store: MockSpaceNameStore) -> SwitcherViewModel {
    let ds = MutableMockDataSource()
    ds.displaySpaces = [
      display(
        uuid: "display-1",
        spaces: [space(id: 1, uuid: "uuid-1"), space(id: 2, uuid: "uuid-2")],
        current: 1),
      display(uuid: "display-2", spaces: [space(id: 3, uuid: "uuid-3")], current: 3),
    ]
    ds.windowList = [
      window(id: 10, owner: "Safari", name: "Google", pid: 100),
      window(id: 20, owner: "Terminal", name: "bash", pid: 200),
      window(id: 30, owner: "Code", name: "main.swift", pid: 300),
    ]
    ds.windowSpaces = [10: [1], 20: [2], 30: [3]]
    return makeTestSwitcherViewModel(
      spaceManager: SpaceManager(dataSource: ds), spaceNameStore: store)
  }

  @Test("Space-move mode refuses a Default Space")
  func spaceMoveModeRefusesDefaultSpace() {
    let store = MockSpaceNameStore()
    store.setCustomName(SpaceNameStore.defaultSpaceName, forSpaceUUID: "uuid-3")
    let vm = makeViewModel(store: store)
    vm.refresh()

    vm.selectedItem = .spaceHeader(3)
    vm.toggleSpaceMoveMode()
    #expect(vm.spaceMoveMode == false)
    #expect(vm.sortOverlayText?.contains(SpaceNameStore.defaultSpaceName) == true)
  }

  @Test("Space-move mode still marks a renamed (unpinned) space")
  func renamedSpaceIsMovable() {
    let store = MockSpaceNameStore()
    store.setCustomName("Scratch", forSpaceUUID: "uuid-3")
    let vm = makeViewModel(store: store)
    vm.refresh()

    vm.selectedItem = .spaceHeader(3)
    vm.toggleSpaceMoveMode()
    #expect(vm.spaceMoveMode == true)
  }
}
