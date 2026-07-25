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

/// display-upper (spaces 1, 2) stacked above display-lower (spaces 3, 4),
/// every space holding one window (10/20/30/40).
private func makeStackedScenario() -> MutableMockDataSource {
  let ds = MutableMockDataSource()
  ds.displaySpaces = [
    display(
      uuid: "display-upper",
      spaces: [space(id: 1, uuid: "uuid-1"), space(id: 2, uuid: "uuid-2")],
      current: 1),
    display(
      uuid: "display-lower",
      spaces: [space(id: 3, uuid: "uuid-3"), space(id: 4, uuid: "uuid-4")],
      current: 3),
  ]
  ds.windowList = [
    window(id: 10, owner: "Safari", name: "Google", pid: 100),
    window(id: 20, owner: "Terminal", name: "bash", pid: 200),
    window(id: 30, owner: "Code", name: "main.swift", pid: 300),
    window(id: 40, owner: "Mail", name: "Inbox", pid: 400),
  ]
  ds.windowSpaces = [10: [1], 20: [2], 30: [3], 40: [4]]
  return ds
}

private func stackedArrangement() -> DisplayArrangement {
  DisplayArrangement(displays: [
    .init(uuid: "display-upper", frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080)),
    .init(uuid: "display-lower", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
  ])
}

/// Mode 3 view model. `displayOrder` deliberately leads with the LOWER
/// display (MRU order), which differs from the spatial top-to-bottom order —
/// vertical crossing must follow the arrangement, not displayOrder.
private func makeViewModel(arranged: Bool) -> SwitcherViewModel {
  let vm = SwitcherViewModel(spaceManager: SpaceManager(dataSource: makeStackedScenario()))
  if arranged { vm.displayArrangement = stackedArrangement() }
  vm.refresh()
  vm.displayOrder = ["display-lower", "display-upper"]
  return vm
}

private func sections(_ vm: SwitcherViewModel, on uuid: String) -> [SwitcherSection] {
  vm.filteredSections.filter { $0.displayUUID == uuid }
}

private func firstItem(of section: SwitcherSection) -> SelectedItem {
  section.windows.first.map { .windowRow($0.id) } ?? .spaceHeader(section.id)
}

@Suite("Vertical Space Navigation")
struct VerticalSpaceNavigationTests {

  @Test("Stepping within a display is unchanged")
  func withinDisplayStepping() {
    let vm = makeViewModel(arranged: true)
    let lower = sections(vm, on: "display-lower")
    vm.selectedItem = firstItem(of: lower[0])
    vm.moveToNextSpace()
    #expect(vm.selectedItem == firstItem(of: lower[1]))
  }

  @Test("Down from a display's last space enters the display below at its first space")
  func downCrossesToDisplayBelow() {
    let vm = makeViewModel(arranged: true)
    let upper = sections(vm, on: "display-upper")
    let lower = sections(vm, on: "display-lower")
    vm.selectedItem = firstItem(of: upper[upper.count - 1])
    vm.moveToNextSpace()
    #expect(vm.selectedItem == firstItem(of: lower[0]))
  }

  @Test("Up from a display's first space enters the display above at its last space")
  func upCrossesToDisplayAbove() {
    let vm = makeViewModel(arranged: true)
    let upper = sections(vm, on: "display-upper")
    let lower = sections(vm, on: "display-lower")
    vm.selectedItem = firstItem(of: lower[0])
    vm.moveToPreviousSpace()
    #expect(vm.selectedItem == firstItem(of: upper[upper.count - 1]))
  }

  @Test("Down from the bottom display's last space wraps to the top display's first")
  func downAtBottomWrapsToTop() {
    let vm = makeViewModel(arranged: true)
    let upper = sections(vm, on: "display-upper")
    let lower = sections(vm, on: "display-lower")
    vm.selectedItem = firstItem(of: lower[lower.count - 1])
    vm.moveToNextSpace()
    #expect(vm.selectedItem == firstItem(of: upper[0]))
  }

  @Test("Up from the top display's first space wraps to the bottom display's last")
  func upAtTopWrapsToBottom() {
    let vm = makeViewModel(arranged: true)
    let upper = sections(vm, on: "display-upper")
    let lower = sections(vm, on: "display-lower")
    vm.selectedItem = firstItem(of: upper[0])
    vm.moveToPreviousSpace()
    #expect(vm.selectedItem == firstItem(of: lower[lower.count - 1]))
  }

  @Test("Without an arrangement, group-boundary stops behave as before")
  func withoutArrangementKeepsGroupStops() {
    let vm = makeViewModel(arranged: false)
    let lower = sections(vm, on: "display-lower")
    // display-lower leads displayOrder, so its last space is a group end —
    // the legacy behavior stops at the .spaces row there.
    vm.selectedItem = firstItem(of: lower[lower.count - 1])
    vm.moveToNextSpace()
    #expect(vm.selectedItem == .spaces)
  }
}
