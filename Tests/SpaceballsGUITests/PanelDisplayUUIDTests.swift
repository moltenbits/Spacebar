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

/// display-a (space 1 with window 10) and display-b (space 2 with window 20,
/// space 3 empty).
private func makeTwoDisplayScenario() -> MutableMockDataSource {
  let ds = MutableMockDataSource()
  ds.displaySpaces = [
    display(uuid: "display-a", spaces: [space(id: 1, uuid: "uuid-1")], current: 1),
    display(
      uuid: "display-b",
      spaces: [space(id: 2, uuid: "uuid-2"), space(id: 3, uuid: "uuid-3")],
      current: 2),
  ]
  ds.windowList = [
    window(id: 10, owner: "Safari", name: "Google", pid: 100),
    window(id: 20, owner: "Terminal", name: "bash", pid: 200),
  ]
  ds.windowSpaces = [10: [1], 20: [2]]
  return ds
}

/// Mode 3 view model over the two-display scenario, meta rows on display-a.
private func makeViewModel() -> SwitcherViewModel {
  let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeTwoDisplayScenario()))
  vm.refresh()
  vm.displayOrder = ["display-a", "display-b"]
  vm.metaRowsDisplayUUID = "display-a"
  return vm
}

@Suite("Panel display UUID for selection")
struct PanelDisplayUUIDTests {

  @Test("Window row maps to the display of its section")
  func windowRowMapsToItsDisplay() {
    let vm = makeViewModel()
    #expect(vm.panelDisplayUUID(for: .windowRow(10)) == "display-a")
    #expect(vm.panelDisplayUUID(for: .windowRow(20)) == "display-b")
  }

  @Test("Space header maps to its display, including empty spaces")
  func spaceHeaderMapsToItsDisplay() {
    let vm = makeViewModel()
    #expect(vm.panelDisplayUUID(for: .spaceHeader(1)) == "display-a")
    #expect(vm.panelDisplayUUID(for: .spaceHeader(3)) == "display-b")
  }

  @Test("Meta rows map to the meta-rows display")
  func metaRowsMapToMetaDisplay() {
    let vm = makeViewModel()
    #expect(vm.panelDisplayUUID(for: .spaces) == "display-a")
    #expect(vm.panelDisplayUUID(for: .settings) == "display-a")
    #expect(vm.panelDisplayUUID(for: .eject) == "display-a")
  }

  @Test("Meta rows map to nil when no meta-rows display is set (modes 1/2)")
  func metaRowsNilWithoutMetaDisplay() {
    let vm = makeViewModel()
    vm.metaRowsDisplayUUID = nil
    #expect(vm.panelDisplayUUID(for: .spaces) == nil)
    #expect(vm.panelDisplayUUID(for: .settings) == nil)
    #expect(vm.panelDisplayUUID(for: .eject) == nil)
  }

  @Test("Nil and stale selections map to nil")
  func nilAndStaleSelectionsMapToNil() {
    let vm = makeViewModel()
    #expect(vm.panelDisplayUUID(for: nil) == nil)
    #expect(vm.panelDisplayUUID(for: .windowRow(999)) == nil)
    #expect(vm.panelDisplayUUID(for: .spaceHeader(999)) == nil)
  }
}
