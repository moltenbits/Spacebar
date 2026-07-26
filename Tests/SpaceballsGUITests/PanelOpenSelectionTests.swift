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

/// display-solo holds ONE space with ONE window (the active app); display-b
/// holds two spaces with a window each.
private func makeSoloScenario(
  soloWindowCount: Int = 1, soloSpaceCount: Int = 1
) -> MutableMockDataSource {
  let ds = MutableMockDataSource()
  var soloSpaces = [space(id: 1, uuid: "uuid-1")]
  if soloSpaceCount > 1 {
    soloSpaces.append(space(id: 4, uuid: "uuid-4"))
  }
  ds.displaySpaces = [
    display(uuid: "display-solo", spaces: soloSpaces, current: 1),
    display(
      uuid: "display-b",
      spaces: [space(id: 2, uuid: "uuid-2"), space(id: 3, uuid: "uuid-3")],
      current: 2),
  ]
  ds.windowList = [
    window(id: 10, owner: "iTerm2", name: "shell", pid: 100),
    window(id: 20, owner: "Safari", name: "Google", pid: 200),
    window(id: 30, owner: "Mail", name: "Inbox", pid: 300),
  ]
  ds.windowSpaces = [10: [1], 20: [2], 30: [3]]
  if soloWindowCount > 1 {
    ds.windowList.append(window(id: 11, owner: "Code", name: "main.swift", pid: 400))
    ds.windowSpaces[11] = [1]
  }
  return ds
}

private func makeViewModel(_ ds: MutableMockDataSource) -> SwitcherViewModel {
  let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: ds))
  vm.refresh()
  vm.displayOrder = ["display-solo", "display-b"]
  vm.resetSelection()
  return vm
}

@Suite("Panel Open Selection")
struct PanelOpenSelectionTests {

  @Test("The active window alone on its display's only space holds the initial selection")
  func soloWindowOnSoloSpaceHolds() {
    let vm = makeViewModel(makeSoloScenario())
    #expect(vm.selectedItem == .windowRow(10))
    #expect(vm.shouldKeepInitialSelectionOnOpen)
  }

  @Test("A display with more than one space advances as usual")
  func multipleSpacesAdvance() {
    let vm = makeViewModel(makeSoloScenario(soloSpaceCount: 2))
    #expect(!vm.shouldKeepInitialSelectionOnOpen)
  }

  @Test("A space with more than one window advances as usual")
  func multipleWindowsAdvance() {
    let vm = makeViewModel(makeSoloScenario(soloWindowCount: 2))
    #expect(!vm.shouldKeepInitialSelectionOnOpen)
  }

  @Test("A selection that is not a window row advances as usual")
  func nonWindowSelectionAdvances() {
    let vm = makeViewModel(makeSoloScenario())
    vm.selectedItem = .spaces
    #expect(!vm.shouldKeepInitialSelectionOnOpen)
  }
}
