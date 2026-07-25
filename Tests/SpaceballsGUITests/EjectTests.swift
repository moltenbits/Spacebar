import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Helpers (local to this suite)

private func desktop(
  id: UInt64, uuid: String, display: String, current: Bool = false
) -> SpaceInfo {
  SpaceInfo(id: id, uuid: uuid, type: .desktop, displayUUID: display, isCurrent: current)
}

private let defaultName = SpaceNameStore.defaultSpaceName

/// builtin "b": space 1 (current). External "d1": Default Space (2), "Work"
/// (3, current), unnamed (4). External "d2": two unnamed spaces (5 current, 6)
/// and NO Default Space.
private func makeEjectScenario() -> (spaces: [SpaceInfo], names: [String: String]) {
  let spaces = [
    desktop(id: 1, uuid: "u1", display: "b", current: true),
    desktop(id: 2, uuid: "u2", display: "d1"),
    desktop(id: 3, uuid: "u3", display: "d1", current: true),
    desktop(id: 4, uuid: "u4", display: "d1"),
    desktop(id: 5, uuid: "u5", display: "d2", current: true),
    desktop(id: 6, uuid: "u6", display: "d2"),
  ]
  return (spaces, ["u2": defaultName, "u3": "Work"])
}

@Suite("Eject Planning")
struct EjectPlannerTests {

  @Test("Non-default spaces on external displays are ejected, descending by tile index")
  func planMovesNonDefaultSpacesDescending() {
    let (spaces, names) = makeEjectScenario()
    let plan = EjectPlanner.plan(spaces: spaces, targetDisplayUUID: "b", names: names)

    let d1Moves = plan.moves.filter { $0.sourceDisplayUUID == "d1" }
    #expect(d1Moves.map(\.spaceID) == [4, 3])
    #expect(d1Moves.map(\.sourceIndex) == [2, 1])
    #expect(d1Moves.allSatisfy { $0.targetDisplayUUID == "b" })

    let d2Moves = plan.moves.filter { $0.sourceDisplayUUID == "d2" }
    #expect(d2Moves.map(\.spaceID) == [6, 5])
    #expect(d2Moves.map(\.sourceIndex) == [1, 0])
  }

  @Test("The target display's own spaces are never ejected")
  func targetDisplaySkipped() {
    let (spaces, names) = makeEjectScenario()
    let plan = EjectPlanner.plan(spaces: spaces, targetDisplayUUID: "b", names: names)
    #expect(!plan.moves.contains { $0.sourceDisplayUUID == "b" })
  }

  @Test("A display without a Default Space needs one created first")
  func missingDefaultReported() {
    let (spaces, names) = makeEjectScenario()
    let plan = EjectPlanner.plan(spaces: spaces, targetDisplayUUID: "b", names: names)
    #expect(plan.displaysNeedingDefault == ["d2"])
  }

  @Test("A display whose current space is ejected pre-switches to its Default Space")
  func preSwitchToDefault() {
    let (spaces, names) = makeEjectScenario()
    let plan = EjectPlanner.plan(spaces: spaces, targetDisplayUUID: "b", names: names)
    // d1's current space ("Work", index 1) is being ejected; its Default
    // Space sits at index 0. d2 has no default yet, so no pre-switch there.
    #expect(
      plan.preSwitches == [
        EjectPlanner.PreSwitch(displayUUID: "d1", toSpaceIndex: 0, toSpaceID: 2)
      ])
  }

  @Test("A display already sitting on its Default Space needs no pre-switch")
  func noPreSwitchWhenDefaultIsCurrent() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
      desktop(id: 3, uuid: "u3", display: "d1"),
    ]
    let plan = EjectPlanner.plan(
      spaces: spaces, targetDisplayUUID: "b", names: ["u2": defaultName])
    #expect(plan.preSwitches.isEmpty)
    #expect(plan.moves.map(\.spaceID) == [3])
  }

  @Test("A display holding only its Default Space contributes nothing")
  func defaultOnlyDisplayContributesNothing() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
    let plan = EjectPlanner.plan(
      spaces: spaces, targetDisplayUUID: "b", names: ["u2": defaultName])
    #expect(plan.moves.isEmpty)
    #expect(plan.displaysNeedingDefault.isEmpty)
    #expect(plan.preSwitches.isEmpty)
  }
}

@Suite("Restore Planning")
struct RestorePlannerTests {

  /// Everything got ejected onto builtin "b": its own space 1, then restored
  /// candidates 3 ("Work" from d1), 4 (from d1), 9 (from a display that is
  /// still disconnected). d1 is back with its Default Space (2). Record u99
  /// refers to a space that no longer exists.
  private func makeRestoreScenario() -> (spaces: [SpaceInfo], pending: [String: String]) {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b"),
      desktop(id: 3, uuid: "u3", display: "b", current: true),
      desktop(id: 4, uuid: "u4", display: "b"),
      desktop(id: 9, uuid: "u9", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
    let pending = ["u3": "d1", "u4": "d1", "u9": "gone", "u99": "d1"]
    return (spaces, pending)
  }

  @Test("Spaces whose display is back are restored, descending by tile index")
  func restorableMovesDescending() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.moves.map(\.spaceID) == [4, 3])
    #expect(plan.moves.map(\.sourceIndex) == [2, 1])
    #expect(plan.moves.allSatisfy { $0.targetDisplayUUID == "d1" })
  }

  @Test("A record whose display is still missing stays pending")
  func missingDisplayKeepsWaiting() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.waiting == ["u9"])
    #expect(!plan.moves.contains { $0.spaceUUID == "u9" })
  }

  @Test("A record whose space no longer exists is dropped")
  func staleRecordDropped() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.stale == ["u99"])
  }

  @Test("A space already back home is completed without a move")
  func alreadyHomeCompleted() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "d1", current: true),
    ]
    let plan = RestorePlanner.plan(spaces: spaces, pending: ["u3": "d1"])
    #expect(plan.completed == ["u3"])
    #expect(plan.moves.isEmpty)
  }

  @Test("Restoring the source display's current space pre-switches to a staying space")
  func preSwitchOffRestoredCurrentSpace() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    // Space 3 is builtin's current space and is being restored — switch the
    // display to its first non-restored desktop (space 1, index 0) first.
    #expect(
      plan.preSwitches == [
        EjectPlanner.PreSwitch(displayUUID: "b", toSpaceIndex: 0, toSpaceID: 1)
      ])
  }
}

@Suite("Eject Store")
struct EjectStoreTests {

  private func makeStore() -> (EjectStore, UserDefaults) {
    let suite = "eject-store-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (EjectStore(defaults: defaults), defaults)
  }

  @Test("Records round-trip and clear individually")
  func recordsRoundTrip() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u5", originalDisplayUUID: "d2")
    #expect(store.pendingEjections() == ["u3": "d1", "u5": "d2"])

    store.clearEjection(spaceUUID: "u3")
    #expect(store.pendingEjections() == ["u5": "d2"])
  }

  @Test("Re-recording a space overwrites its display")
  func reRecordOverwrites() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    #expect(store.pendingEjections() == ["u3": "d2"])
  }

  @Test("Arming round-trips and clears with the record")
  func armingRoundTrips() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u5", originalDisplayUUID: "d2")
    #expect(store.armedEjections().isEmpty)

    store.armEjections(spaceUUIDs: ["u3"])
    #expect(store.armedEjections() == ["u3"])
    // Arming leaves the records themselves untouched.
    #expect(store.pendingEjections() == ["u3": "d1", "u5": "d2"])

    store.clearEjection(spaceUUID: "u3")
    #expect(store.armedEjections().isEmpty)
  }

  @Test("Re-recording an armed space disarms it")
  func reRecordDisarms() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.armEjections(spaceUUIDs: ["u3"])
    // A fresh eject of the same space (its display is present again) must
    // start unarmed — the display has to go away again before auto-restore.
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    #expect(store.armedEjections().isEmpty)
  }
}
