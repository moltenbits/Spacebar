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
        EjectPlanner.PreSwitch(displayUUID: "d1", toSpaceID: 2)
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

  @Test("The active space of each ejecting display is captured")
  func activeSpacesCaptured() {
    let (spaces, names) = makeEjectScenario()
    let plan = EjectPlanner.plan(spaces: spaces, targetDisplayUUID: "b", names: names)
    // d1's active space is "Work" (u3), d2's is u5 — captured so restore can
    // reactivate them. The built-in display is never captured.
    #expect(plan.activeSpaceByDisplay == ["d1": "u3", "d2": "u5"])
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
  private func makeRestoreScenario() -> (spaces: [SpaceInfo], pending: [String: [String]]) {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b"),
      desktop(id: 3, uuid: "u3", display: "b", current: true),
      desktop(id: 4, uuid: "u4", display: "b"),
      desktop(id: 9, uuid: "u9", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
    let pending = ["u3": ["d1"], "u4": ["d1"], "u9": ["gone"], "u99": ["d1"]]
    return (spaces, pending)
  }

  @Test("Spaces whose display is back are restored, descending by tile index")
  func restorableMovesDescending() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.moves.map(\.spaceID) == [4, 3])
    #expect(plan.moves.map(\.sourceIndex) == [2, 1])
    #expect(plan.moves.allSatisfy { $0.targetDisplayUUID == "d1" })
    // Each move names the recorded origin it satisfies, so only that origin
    // is cleared once the move verifies.
    #expect(plan.restoredOrigins == ["u3": "d1", "u4": "d1"])
  }

  @Test("A record whose display is still missing stays pending")
  func missingDisplayKeepsWaiting() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.waiting == ["u9"])
    #expect(!plan.moves.contains { $0.spaceUUID == "u9" })
  }

  @Test("A missing Space whose display is disconnected stays pending")
  func missingSpaceOnDisconnectedDisplayKeepsWaiting() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true)
    ]
    let plan = RestorePlanner.plan(spaces: spaces, pending: ["u99": ["d1"]])

    #expect(plan.waiting == ["u99"])
    #expect(plan.stale.isEmpty)
  }

  @Test("Restoring one display preserves missing Spaces for disconnected displays")
  func mixedDisplayGroupsRemainIndependent() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
    let pending = ["u3": ["d1"], "u99": ["d2"]]
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)

    #expect(plan.moves.map(\.spaceUUID) == ["u3"])
    #expect(plan.waiting == ["u99"])
    #expect(plan.stale.isEmpty)
  }

  @Test("A record whose space no longer exists is dropped")
  func staleRecordDropped() {
    let (spaces, pending) = makeRestoreScenario()
    let plan = RestorePlanner.plan(spaces: spaces, pending: pending)
    #expect(plan.stale == [EjectRecord(spaceUUID: "u99", displayUUID: "d1")])
  }

  @Test("A space already back home is completed without a move")
  func alreadyHomeCompleted() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "d1", current: true),
    ]
    let plan = RestorePlanner.plan(spaces: spaces, pending: ["u3": ["d1"]])
    #expect(plan.completed == [EjectRecord(spaceUUID: "u3", displayUUID: "d1")])
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
        EjectPlanner.PreSwitch(displayUUID: "b", toSpaceID: 1)
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

  @Test("Records round-trip and clear per origin")
  func recordsRoundTrip() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u5", originalDisplayUUID: "d2")
    #expect(store.pendingEjections() == ["u3": ["d1"], "u5": ["d2"]])

    store.clearEjection(spaceUUID: "u3", displayUUID: "d1")
    #expect(store.pendingEjections() == ["u5": ["d2"]])
  }

  @Test("Ejecting a space from another display adds an origin, most recent last")
  func reRecordAppendsOrigin() {
    let (store, _) = makeStore()
    // Ejected at the office (d1), moved onto the home monitor, ejected again
    // there (d2): both origins survive, ordered by recency.
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    #expect(store.pendingEjections() == ["u3": ["d1", "d2"]])

    // Re-ejecting from a display already on record moves it to the end.
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    #expect(store.pendingEjections() == ["u3": ["d2", "d1"]])
  }

  @Test("Clearing one origin leaves the space's other origins")
  func clearingOneOriginKeepsOthers() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")

    store.clearEjection(spaceUUID: "u3", displayUUID: "d1")
    #expect(store.pendingEjections() == ["u3": ["d2"]])

    store.clearEjection(spaceUUID: "u3", displayUUID: "d2")
    #expect(store.pendingEjections().isEmpty)
  }

  @Test("Superseded origins are removed together")
  func removeOrigins() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d3")

    store.removeOrigins(spaceUUID: "u3", displayUUIDs: ["d1", "d3"])
    #expect(store.pendingEjections() == ["u3": ["d2"]])

    // Removing an origin that isn't there is a no-op.
    store.removeOrigins(spaceUUID: "u3", displayUUIDs: ["d9"])
    #expect(store.pendingEjections() == ["u3": ["d2"]])
  }

  @Test("Legacy single-origin records read as one-element origin lists")
  func legacyRecordsMigrate() {
    let (store, defaults) = makeStore()
    defaults.set(["u3": "d1", "u5": "d2"], forKey: "ejectedSpaces")
    #expect(store.pendingEjections() == ["u3": ["d1"], "u5": ["d2"]])

    // Writing through the store upgrades the persisted shape.
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    #expect(store.pendingEjections() == ["u3": ["d1", "d2"], "u5": ["d2"]])
  }

  @Test("Arming is per display and prunes with that display's last record")
  func armingRoundTrips() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u5", originalDisplayUUID: "d2")
    #expect(store.armedDisplays().isEmpty)

    store.armDisplays(["d1"])
    #expect(store.armedDisplays() == ["d1"])
    // Arming leaves the records themselves untouched.
    #expect(store.pendingEjections() == ["u3": ["d1"], "u5": ["d2"]])

    store.clearEjection(spaceUUID: "u3", displayUUID: "d1")
    #expect(store.armedDisplays().isEmpty)
  }

  @Test("A fresh eject from a display disarms it")
  func reRecordDisarms() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.armDisplays(["d1"])
    // A fresh eject from d1 means d1 is present again — it has to go away
    // again before auto-restore may touch its records.
    store.recordEjection(spaceUUID: "u4", originalDisplayUUID: "d1")
    #expect(store.armedDisplays().isEmpty)
  }

  @Test("An armed display stays armed while another site's origin references it")
  func armingSurvivesOtherOriginClear() {
    let (store, _) = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    store.armDisplays(["d1", "d2"])

    store.clearEjection(spaceUUID: "u3", displayUUID: "d2")
    #expect(store.armedDisplays() == ["d1"])
  }

  @Test("Legacy armed space lists migrate to their origin displays")
  func legacyArmedMigrates() {
    let (store, defaults) = makeStore()
    defaults.set(["u3": "d1", "u5": "d2"], forKey: "ejectedSpaces")
    defaults.set(["u3"], forKey: "armedEjectedSpaces")

    #expect(store.armedDisplays() == ["d1"])
    #expect(defaults.object(forKey: "armedEjectedSpaces") == nil)
  }

  @Test("Active-space records round-trip, overwrite per display, and clear")
  func activeSpaceRecordsRoundTrip() {
    let (store, _) = makeStore()
    store.recordActiveSpace(displayUUID: "d1", spaceUUID: "u3")
    store.recordActiveSpace(displayUUID: "d2", spaceUUID: "u5")
    #expect(store.activeSpaceRecords() == ["d1": "u3", "d2": "u5"])

    // A later eject overwrites per display, leaving other displays' records.
    store.recordActiveSpace(displayUUID: "d1", spaceUUID: "u4")
    #expect(store.activeSpaceRecords() == ["d1": "u4", "d2": "u5"])

    store.clearActiveSpace(displayUUID: "d1")
    #expect(store.activeSpaceRecords() == ["d2": "u5"])
  }
}

// MARK: - Display Fingerprints

private func fingerprint(
  vendor: UInt32 = 100, model: UInt32 = 200, serial: UInt32 = 0,
  x: Double = 0, y: Double = 0
) -> DisplayFingerprint {
  DisplayFingerprint(
    vendorNumber: vendor, modelNumber: model, serialNumber: serial,
    originX: x, originY: y)
}

@Suite("Display Fingerprint Matching")
struct DisplayFingerprintTests {

  @Test("A unique hardware match wins regardless of its new UUID")
  func uniqueHardwareMatch() {
    let connected = [
      "new-uuid": fingerprint(vendor: 1, model: 2, serial: 3),
      "other": fingerprint(vendor: 9, model: 9, serial: 9),
    ]
    #expect(
      DisplayFingerprint.match(
        recorded: fingerprint(vendor: 1, model: 2, serial: 3, x: 500),
        connected: connected) == "new-uuid")
  }

  @Test("Identical twin displays tie-break by arrangement position")
  func twinsTieBreakByPosition() {
    let connected = [
      "left": fingerprint(x: -1800, y: 0),
      "right": fingerprint(x: 1800, y: 0),
    ]
    #expect(
      DisplayFingerprint.match(
        recorded: fingerprint(x: 1790, y: 10), connected: connected) == "right")
    #expect(
      DisplayFingerprint.match(
        recorded: fingerprint(x: -1750, y: 0), connected: connected) == "left")
  }

  @Test("Different hardware never matches")
  func differentHardwareNoMatch() {
    #expect(
      DisplayFingerprint.match(
        recorded: fingerprint(vendor: 1),
        connected: ["x": fingerprint(vendor: 2)]) == nil)
  }

  @Test("Fingerprints round-trip through their plist dictionary form")
  func dictionaryRoundTrip() {
    let original = fingerprint(vendor: 10, model: 20, serial: 30, x: -1800, y: 42)
    #expect(DisplayFingerprint(dictionary: original.dictionary) == original)
  }
}

@Suite("Restore Planning With Fingerprints")
struct RestoreFingerprintPlanningTests {

  @Test("A recorded display that returns under a new UUID is matched by hardware and remapped")
  func remapsToReassignedUUID() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d-new", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-old"]],
      recordedFingerprints: ["d-old": fingerprint()],
      connectedFingerprints: ["b": fingerprint(vendor: 9), "d-new": fingerprint()])

    #expect(plan.moves.map(\.spaceUUID) == ["u3"])
    #expect(plan.moves[0].targetDisplayUUID == "d-new")
    #expect(plan.displayRemap == ["d-old": "d-new"])
    // The origin to clear is the RECORDED UUID, not the remapped one.
    #expect(plan.restoredOrigins == ["u3": "d-old"])
    #expect(plan.waiting.isEmpty)
  }

  @Test("A space already sitting on the remapped display is completed")
  func completedViaRemap() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "d-new", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-old"]],
      recordedFingerprints: ["d-old": fingerprint()],
      connectedFingerprints: ["b": fingerprint(vendor: 9), "d-new": fingerprint()])

    #expect(plan.completed == [EjectRecord(spaceUUID: "u3", displayUUID: "d-old")])
    #expect(plan.moves.isEmpty)
  }

  @Test("An exactly-matching connected UUID wins over any fingerprint twin")
  func exactUUIDBeatsFingerprint() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
      desktop(id: 4, uuid: "u4", display: "d-twin", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d1"]],
      recordedFingerprints: ["d1": fingerprint()],
      connectedFingerprints: ["d1": fingerprint(), "d-twin": fingerprint()])

    #expect(plan.moves.map(\.targetDisplayUUID) == ["d1"])
    #expect(plan.displayRemap.isEmpty)
  }

  @Test("Without a recorded fingerprint an absent display still waits")
  func legacyRecordsKeepWaiting() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-old"]],
      recordedFingerprints: [:],
      connectedFingerprints: ["b": fingerprint()])
    #expect(plan.waiting == ["u3"])
  }

  @Test("A fingerprint with no hardware match keeps waiting")
  func unmatchedFingerprintWaits() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-old"]],
      recordedFingerprints: ["d-old": fingerprint(vendor: 1)],
      connectedFingerprints: ["b": fingerprint(vendor: 2)])
    #expect(plan.waiting == ["u3"])
    #expect(plan.displayRemap.isEmpty)
  }

  @Test("A missing Space waits when its fingerprint has no connected match")
  func missingSpaceWithUnmatchedFingerprintWaits() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true)
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u99": ["d-old"]],
      recordedFingerprints: ["d-old": fingerprint(vendor: 1)],
      connectedFingerprints: ["b": fingerprint(vendor: 2)])

    #expect(plan.waiting == ["u99"])
    #expect(plan.stale.isEmpty)
    #expect(plan.displayRemap.isEmpty)
  }

  @Test("A missing Space is stale after its display resolves by fingerprint")
  func missingSpaceWithMatchedFingerprintIsStale() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d-new", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u99": ["d-old"]],
      recordedFingerprints: ["d-old": fingerprint(vendor: 1)],
      connectedFingerprints: ["b": fingerprint(vendor: 2), "d-new": fingerprint(vendor: 1)])

    #expect(plan.stale == [EjectRecord(spaceUUID: "u99", displayUUID: "d-old")])
    #expect(plan.waiting.isEmpty)
    #expect(plan.displayRemap == ["d-old": "d-new"])
  }
}

@Suite("Eject Store Fingerprints")
struct EjectStoreFingerprintTests {

  private func makeStore() -> EjectStore {
    let suite = "eject-store-fp-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return EjectStore(defaults: defaults)
  }

  @Test("Fingerprints round-trip and prune with their last referencing record")
  func roundTripAndPrune() {
    let store = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u4", originalDisplayUUID: "d1")
    store.recordDisplayFingerprint(displayUUID: "d1", fingerprint: fingerprint(x: 5))
    #expect(store.displayFingerprints() == ["d1": fingerprint(x: 5)])

    store.clearEjection(spaceUUID: "u3", displayUUID: "d1")
    // d1 is still referenced by u4's record — fingerprint kept.
    #expect(store.displayFingerprints() == ["d1": fingerprint(x: 5)])

    store.clearEjection(spaceUUID: "u4", displayUUID: "d1")
    #expect(store.displayFingerprints().isEmpty)
  }

  @Test("A fingerprint survives while another origin of the same space references it")
  func fingerprintKeptByOtherOrigin() {
    let store = makeStore()
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d1")
    store.recordEjection(spaceUUID: "u3", originalDisplayUUID: "d2")
    store.recordDisplayFingerprint(displayUUID: "d1", fingerprint: fingerprint(x: 1))
    store.recordDisplayFingerprint(displayUUID: "d2", fingerprint: fingerprint(x: 2))

    store.clearEjection(spaceUUID: "u3", displayUUID: "d2")
    #expect(store.displayFingerprints() == ["d1": fingerprint(x: 1)])
  }
}

@Suite("Restore Planning With Multiple Origins")
struct RestoreMultiOriginPlanningTests {

  /// Builtin "b" holds its own space 1 and the parked space 3. External "d1"
  /// (back) holds its Default Space 2. "d-home" is the other site's monitor,
  /// currently disconnected.
  private func makeTwoSiteScenario() -> [SpaceInfo] {
    [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
  }

  @Test("A space ejected at two sites restores to whichever origin is connected")
  func connectedOriginWins() {
    let plan = RestorePlanner.plan(
      spaces: makeTwoSiteScenario(), pending: ["u3": ["d1", "d-home"]],
      parkedDisplayUUID: "b")

    #expect(plan.moves.map(\.spaceUUID) == ["u3"])
    #expect(plan.moves[0].targetDisplayUUID == "d1")
    #expect(plan.restoredOrigins == ["u3": "d1"])
    #expect(plan.waiting.isEmpty)
  }

  @Test("The most recently recorded connected origin wins when several are connected")
  func mostRecentConnectedOriginWins() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "b"),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
      desktop(id: 4, uuid: "u4", display: "d2", current: true),
    ]
    let plan = RestorePlanner.plan(spaces: spaces, pending: ["u3": ["d1", "d2"]])

    #expect(plan.moves.map(\.targetDisplayUUID) == ["d2"])
    #expect(plan.restoredOrigins == ["u3": "d2"])
  }

  @Test("A space already on its connected origin is completed for that origin only")
  func completedForConnectedOriginOnly() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 3, uuid: "u3", display: "d1", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-home", "d1"]], parkedDisplayUUID: "b")

    #expect(plan.completed == [EjectRecord(spaceUUID: "u3", displayUUID: "d1")])
    #expect(plan.moves.isEmpty)
    #expect(plan.waiting.isEmpty)
  }

  @Test("A space parked on the built-in display with only absent origins waits")
  func parkedSpaceWaits() {
    let plan = RestorePlanner.plan(
      spaces: makeTwoSiteScenario(), pending: ["u3": ["d-home"]], parkedDisplayUUID: "b")

    #expect(plan.waiting == ["u3"])
    #expect(plan.moves.isEmpty)
  }

  @Test("A space placed on an external display is not waiting for another site's monitor")
  func placedSpaceIsNotWaiting() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
      desktop(id: 3, uuid: "u3", display: "d1"),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u3": ["d-home"]], parkedDisplayUUID: "b")

    #expect(plan.waiting.isEmpty)
    #expect(plan.moves.isEmpty)
    #expect(plan.completed.isEmpty)
    #expect(plan.stale.isEmpty)
    #expect(plan.isEmpty)
  }

  @Test("Without a parked display every unresolvable record waits, as before")
  func legacyWaitingSemanticsWithoutParkedDisplay() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
      desktop(id: 3, uuid: "u3", display: "d1"),
    ]
    let plan = RestorePlanner.plan(spaces: spaces, pending: ["u3": ["d-home"]])
    #expect(plan.waiting == ["u3"])
  }

  @Test("A missing space with a connected origin is stale for that origin only")
  func staleForConnectedOriginOnly() {
    let spaces = [
      desktop(id: 1, uuid: "u1", display: "b", current: true),
      desktop(id: 2, uuid: "u2", display: "d1", current: true),
    ]
    let plan = RestorePlanner.plan(
      spaces: spaces, pending: ["u99": ["d-home", "d1"]], parkedDisplayUUID: "b")

    #expect(plan.stale == [EjectRecord(spaceUUID: "u99", displayUUID: "d1")])
    #expect(plan.waiting.isEmpty)
  }

  @Test("Armed filtering keeps only origins on armed displays")
  func armedFiltering() {
    let pending = ["u3": ["d-home", "d1"], "u4": ["d2"], "u5": ["d1", "d2"]]
    #expect(
      RestorePlanner.armedPending(pending, armedDisplays: ["d1"])
        == ["u3": ["d1"], "u5": ["d1"]])
    #expect(RestorePlanner.armedPending(pending, armedDisplays: []).isEmpty)
  }
}

@Suite("Eject Origin Supersession")
struct EjectOriginSupersessionTests {

  private func resolver(
    connected: Set<String>,
    recorded: [String: DisplayFingerprint] = [:],
    connectedFingerprints: [String: DisplayFingerprint] = [:]
  ) -> DisplayResolver {
    DisplayResolver(
      connectedDisplays: connected, recordedFingerprints: recorded,
      connectedFingerprints: connectedFingerprints)
  }

  @Test("Origins whose display is connected are superseded by a fresh eject")
  func connectedOriginsSuperseded() {
    // The space was ejected from d2 earlier this session, then moved to d1
    // and ejected again: d2's record is stale, d-home's belongs to the other
    // site and must survive.
    #expect(
      EjectPlanner.supersededOrigins(
        existing: ["d-home", "d2"], newOrigin: "d1",
        resolver: resolver(connected: ["b", "d1", "d2"])) == ["d2"])
  }

  @Test("The display being ejected from is never listed as superseded")
  func newOriginNeverSuperseded() {
    #expect(
      EjectPlanner.supersededOrigins(
        existing: ["d1"], newOrigin: "d1", resolver: resolver(connected: ["b", "d1"])
      )
      .isEmpty)
  }

  @Test("Origins whose display is absent survive")
  func absentOriginsSurvive() {
    #expect(
      EjectPlanner.supersededOrigins(
        existing: ["d-home"], newOrigin: "d1", resolver: resolver(connected: ["b", "d1"])
      )
      .isEmpty)
  }

  @Test("An origin whose display is back under a new UUID is superseded by fingerprint")
  func fingerprintResolvedOriginSuperseded() {
    #expect(
      EjectPlanner.supersededOrigins(
        existing: ["d-old"], newOrigin: "d1",
        resolver: resolver(
          connected: ["b", "d1", "d-new"],
          recorded: ["d-old": fingerprint()],
          connectedFingerprints: ["d-new": fingerprint(), "d1": fingerprint(vendor: 7)]))
        == ["d-old"])
  }
}

@Suite("Display Resolver")
struct DisplayResolverTests {

  @Test("An exact connected UUID resolves to itself")
  func exactUUID() {
    let resolver = DisplayResolver(
      connectedDisplays: ["d1"], recordedFingerprints: [:], connectedFingerprints: [:])
    #expect(resolver.resolve("d1") == "d1")
    #expect(resolver.resolve("d2") == nil)
  }

  @Test("A recorded fingerprint resolves to the connected display with the same hardware")
  func fingerprintResolution() {
    let resolver = DisplayResolver(
      connectedDisplays: ["b", "d-new"],
      recordedFingerprints: ["d-old": fingerprint()],
      connectedFingerprints: ["b": fingerprint(vendor: 9), "d-new": fingerprint()])
    #expect(resolver.resolve("d-old") == "d-new")
  }
}
