import Foundation
import Testing

@testable import SpaceballsCore

@Suite("SpaceNameStore")
struct SpaceNameStoreTests {

  private func makeStore() -> SpaceNameStore {
    let suiteName = "com.moltenbits.spaceballs.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    return SpaceNameStore(defaults: defaults)
  }

  @Test("Store and retrieve a custom name")
  func storeAndRetrieve() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "uuid-1")
    #expect(store.customName(forSpaceUUID: "uuid-1") == "Work")
  }

  @Test("Returns nil for unknown UUID")
  func unknownUUID() {
    let store = makeStore()
    #expect(store.customName(forSpaceUUID: "nonexistent") == nil)
  }

  @Test("Setting nil removes the entry")
  func setNilRemoves() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "uuid-1")
    store.setCustomName(nil, forSpaceUUID: "uuid-1")
    #expect(store.customName(forSpaceUUID: "uuid-1") == nil)
  }

  @Test("Setting empty string removes the entry")
  func setEmptyRemoves() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "uuid-1")
    store.setCustomName("", forSpaceUUID: "uuid-1")
    #expect(store.customName(forSpaceUUID: "uuid-1") == nil)
  }

  @Test("Setting whitespace-only string removes the entry")
  func setWhitespaceRemoves() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "uuid-1")
    store.setCustomName("   \n\t  ", forSpaceUUID: "uuid-1")
    #expect(store.customName(forSpaceUUID: "uuid-1") == nil)
  }

  @Test("allCustomNames returns all entries")
  func allNames() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "uuid-1")
    store.setCustomName("Personal", forSpaceUUID: "uuid-2")
    let all = store.allCustomNames()
    #expect(all == ["uuid-1": "Work", "uuid-2": "Personal"])
  }

  @Test("allCustomNames returns empty dict when no names set")
  func allNamesEmpty() {
    let store = makeStore()
    #expect(store.allCustomNames().isEmpty)
  }

  @Test("Workspace name matching ignores stale mappings, fullscreen Spaces, and ordinal aliases")
  func customNameMatchesOnlyLiveDesktop() {
    let store = makeStore()
    store.setCustomName("Work", forSpaceUUID: "stale")
    store.setCustomName("Work", forSpaceUUID: "fullscreen")
    let spaces = [
      SpaceInfo(id: 1, uuid: "desktop", type: .desktop, displayUUID: "display", isCurrent: true),
      SpaceInfo(
        id: 2, uuid: "fullscreen", type: .fullscreen, displayUUID: "display", isCurrent: false),
    ]
    #expect(store.spaceWithCustomName("Work", in: spaces) == nil)
    #expect(store.spaceWithCustomName("Desktop 1", in: spaces) == nil)
    #expect(store.spaceWithCustomName("1", in: spaces) == nil)
    store.setCustomName("Work", forSpaceUUID: "desktop")
    #expect(store.spaceWithCustomName("work", in: spaces)?.id == 1)
  }
}
