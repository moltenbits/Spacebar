import Foundation
import Testing

@testable import SpaceballsCore

@Suite("WindowLayoutStore Persistence")
struct WindowLayoutStorePersistenceTests {

  private func makeDefaults(suite: String = UUID().uuidString) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    // Prevent SpaceNameStore's production migration from importing the app's
    // real names into this isolated suite.
    defaults.set([String: String](), forKey: "customSpaceNames")
    return defaults
  }

  private func makeManager(spaceUUIDs: [String] = []) -> SpaceManager {
    guard !spaceUUIDs.isEmpty else {
      return SpaceManager(dataSource: MockDataSource())
    }
    var ds = MockDataSource()
    ds.displaySpaces = [
      [
        "Display Identifier": "display-A",
        "Spaces": spaceUUIDs.enumerated().map { index, uuid in
          ["ManagedSpaceID": index + 1, "uuid": uuid, "type": 0]
        },
        "Current Space": ["ManagedSpaceID": 1],
      ]
    ]
    return SpaceManager(dataSource: ds)
  }

  private func makeNameStore(
    defaults: UserDefaults,
    names: [String: String] = [:]
  ) -> SpaceNameStore {
    let store = SpaceNameStore(defaults: defaults)
    for (uuid, name) in names {
      store.setCustomName(name, forSpaceUUID: uuid)
    }
    return store
  }

  private func makeStore(
    names: [String: String] = [:],
    currentSpaceUUIDs: [String] = []
  ) -> (WindowLayoutStore, UserDefaults, SpaceNameStore) {
    let defaults = makeDefaults()
    let nameStore = makeNameStore(defaults: defaults, names: names)
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: currentSpaceUUIDs),
      spaceNameStore: nameStore)
    return (store, defaults, nameStore)
  }

  @Test("setFrame + layout round-trip preserves data")
  func roundTrip() {
    let (store, _, _) = makeStore()
    let frame = WindowFrame(x: 100, y: 50, width: 800, height: 600)
    store.setFrame(
      bundleID: "com.example.app", frame: frame,
      spaceUUID: "space-1", displayUUID: "display-A")

    let layout = store.layout(spaceUUID: "space-1", displayUUID: "display-A")
    #expect(layout != nil)
    #expect(layout?.apps["com.example.app"] == frame)
    #expect(layout?.spaceUUID == "space-1")
    #expect(layout?.displayUUID == "display-A")
  }

  @Test("Different (space, display) keys are isolated")
  func keyIsolation() {
    let (store, _, _) = makeStore()
    let frameA = WindowFrame(x: 0, y: 0, width: 100, height: 100)
    let frameB = WindowFrame(x: 200, y: 200, width: 400, height: 400)

    store.setFrame(
      bundleID: "com.app", frame: frameA, spaceUUID: "space-1", displayUUID: "display-A")
    store.setFrame(
      bundleID: "com.app", frame: frameB, spaceUUID: "space-1", displayUUID: "display-B")

    #expect(store.layout(spaceUUID: "space-1", displayUUID: "display-A")?.apps["com.app"] == frameA)
    #expect(store.layout(spaceUUID: "space-1", displayUUID: "display-B")?.apps["com.app"] == frameB)
  }

  @Test("Multiple bundleIDs accumulate in the same (space, display)")
  func multipleBundleIDs() {
    let (store, _, _) = makeStore()
    store.setFrame(
      bundleID: "com.a", frame: WindowFrame(x: 0, y: 0, width: 100, height: 100),
      spaceUUID: "s", displayUUID: "d")
    store.setFrame(
      bundleID: "com.b", frame: WindowFrame(x: 0, y: 0, width: 200, height: 200),
      spaceUUID: "s", displayUUID: "d")

    let layout = store.layout(spaceUUID: "s", displayUUID: "d")
    #expect(layout?.apps.count == 2)
    #expect(layout?.apps["com.a"] != nil)
    #expect(layout?.apps["com.b"] != nil)
  }

  @Test("clearAll empties the store")
  func clearAll() {
    let (store, _, _) = makeStore()
    store.setFrame(
      bundleID: "com.a", frame: WindowFrame(x: 0, y: 0, width: 100, height: 100),
      spaceUUID: "s", displayUUID: "d")
    store.setLastSeenDisplay(spaceUUID: "s", displayUUID: "d")

    store.clearAll()

    #expect(store.layout(spaceUUID: "s", displayUUID: "d") == nil)
    #expect(store.lastSeenDisplayUUID(forSpace: "s") == nil)
  }

  @Test("lastSeenDisplayUUID round-trip")
  func lastSeenRoundTrip() {
    let (store, _, _) = makeStore()
    #expect(store.lastSeenDisplayUUID(forSpace: "s") == nil)
    store.setLastSeenDisplay(spaceUUID: "s", displayUUID: "display-A")
    #expect(store.lastSeenDisplayUUID(forSpace: "s") == "display-A")
    store.setLastSeenDisplay(spaceUUID: "s", displayUUID: "display-B")
    #expect(store.lastSeenDisplayUUID(forSpace: "s") == "display-B")
  }

  @Test("Restore with no saved layout reports no layout")
  func restoreEmpty() {
    let (store, _, _) = makeStore()
    let result = store.restore(spaceUUID: "missing", displayUUID: "missing")
    #expect(!result.hasLayout)
    #expect(result.movedWindows == 0)
  }

  @Test("Layouts persist across store instances on same defaults")
  func persistenceAcrossInstances() {
    let suite = "WindowLayoutStoreTests-" + UUID().uuidString
    let defaults = makeDefaults(suite: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let manager = SpaceManager(dataSource: MockDataSource())
    let names = makeNameStore(defaults: defaults)
    let frame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    do {
      let store = WindowLayoutStore(
        defaults: defaults, spaceManager: manager, spaceNameStore: names)
      store.setFrame(
        bundleID: "com.persisted", frame: frame, spaceUUID: "s-p", displayUUID: "d-p")
      store.setLastSeenDisplay(spaceUUID: "s-p", displayUUID: "d-p")
    }

    let store2 = WindowLayoutStore(
      defaults: defaults, spaceManager: manager, spaceNameStore: names)
    #expect(store2.layout(spaceUUID: "s-p", displayUUID: "d-p")?.apps["com.persisted"] == frame)
    #expect(store2.lastSeenDisplayUUID(forSpace: "s-p") == "d-p")
  }

  @Test("A unique named Space layout follows a recreated macOS Space UUID")
  func namedLayoutSurvivesSpaceRecreation() {
    let defaults = makeDefaults()
    let names = makeNameStore(defaults: defaults, names: ["space-old": "Listenly"])
    let frame = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let original = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-old"]),
      spaceNameStore: names)
    original.setFrame(
      bundleID: "com.googlecode.iterm2", frame: frame,
      spaceUUID: "space-old", displayUUID: "display-A")

    names.setCustomName(nil, forSpaceUUID: "space-old")
    names.setCustomName("Listenly", forSpaceUUID: "space-new")
    let recreated = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    #expect(
      recreated.layout(spaceUUID: "space-new", displayUUID: "display-A")?
        .apps["com.googlecode.iterm2"] == frame)
  }

  @Test("Name identity is case- and whitespace-insensitive across recreation")
  func normalizedNameSurvivesRecreation() {
    let defaults = makeDefaults()
    let names = makeNameStore(defaults: defaults, names: ["space-old": "Listenly"])
    let frame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    let original = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-old"]),
      spaceNameStore: names)
    original.setFrame(
      bundleID: "com.example", frame: frame,
      spaceUUID: "space-old", displayUUID: "display-A")

    names.setCustomName(nil, forSpaceUUID: "space-old")
    names.setCustomName("  LISTENLY  ", forSpaceUUID: "space-new")
    let recreated = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    #expect(
      recreated.layout(spaceUUID: "space-new", displayUUID: "display-A")?
        .apps["com.example"] == frame)
  }

  @Test("Renaming a unique Space migrates its layouts to the new name")
  func renameMigratesLayouts() {
    let defaults = makeDefaults()
    let names = makeNameStore(defaults: defaults, names: ["space-1": "Old Name"])
    let frame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-1"]),
      spaceNameStore: names)
    store.setFrame(
      bundleID: "com.example", frame: frame,
      spaceUUID: "space-1", displayUUID: "display-A")

    names.setCustomName("New Name", forSpaceUUID: "space-1")
    // Recreate immediately, without another layout-store call on the old UUID.
    names.setCustomName(nil, forSpaceUUID: "space-1")
    names.setCustomName("New Name", forSpaceUUID: "space-2")
    let recreated = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-2"]),
      spaceNameStore: names)
    #expect(
      recreated.layout(spaceUUID: "space-2", displayUUID: "display-A")?
        .apps["com.example"] == frame)
  }

  @Test("Duplicate names remain UUID-isolated")
  func duplicateNamesDoNotShareLayouts() {
    let (store, _, _) = makeStore(
      names: ["space-1": "Work", "space-2": "work"],
      currentSpaceUUIDs: ["space-1", "space-2"])
    let frame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    store.setFrame(
      bundleID: "com.example", frame: frame,
      spaceUUID: "space-1", displayUUID: "display-A")

    #expect(
      store.layout(spaceUUID: "space-1", displayUUID: "display-A")?
        .apps["com.example"] == frame)
    #expect(
      store.layout(spaceUUID: "space-2", displayUUID: "display-A") == nil)
  }

  @Test("Unnamed Spaces retain UUID-based isolation")
  func unnamedSpacesRemainUUIDBased() {
    let defaults = makeDefaults()
    let names = makeNameStore(defaults: defaults)
    let frame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    let original = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-old"]),
      spaceNameStore: names)
    original.setFrame(
      bundleID: "com.example", frame: frame,
      spaceUUID: "space-old", displayUUID: "display-A")
    let recreated = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    #expect(recreated.layout(spaceUUID: "space-new", displayUUID: "display-A") == nil)
  }

  @Test("A raw UUID layout migrates to the current unique name")
  func legacyUUIDLayoutMigratesToName() throws {
    let defaults = makeDefaults()
    let frame = WindowFrame(x: 25, y: 30, width: 900, height: 700)
    let legacy = [
      "space-current|display-A": SpaceDisplayLayout(
        spaceUUID: "space-current", displayUUID: "display-A",
        apps: ["com.example": frame],
        capturedAt: Date(timeIntervalSince1970: 100))
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "windowLayouts")
    let names = makeNameStore(
      defaults: defaults, names: ["space-current": "Listenly"])
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-current"]),
      spaceNameStore: names)

    #expect(
      store.layout(spaceUUID: "space-current", displayUUID: "display-A")?
        .apps["com.example"] == frame)
  }

  @Test("Legacy UUID layouts fill missing apps in a partial recreated layout")
  func legacyUUIDLayoutsFillPartialRecreatedLayout() throws {
    let defaults = makeDefaults()
    let currentFrame = WindowFrame(x: 10, y: 20, width: 300, height: 400)
    let olderITermFrame = WindowFrame(x: 20, y: 30, width: 900, height: 700)
    let newerITermFrame = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let safariFrame = WindowFrame(x: 100, y: 80, width: 1200, height: 900)
    let unrelatedFrame = WindowFrame(x: 500, y: 500, width: 400, height: 300)
    let unrelatedCurrentFrame = WindowFrame(x: 700, y: 700, width: 500, height: 500)
    let wrongDisplayFrame = WindowFrame(x: 0, y: 0, width: 3840, height: 2160)
    let legacy = [
      "space-new|display-A": SpaceDisplayLayout(
        spaceUUID: "space-new", displayUUID: "display-A",
        apps: ["com.current": currentFrame],
        capturedAt: Date(timeIntervalSince1970: 400)),
      "oldest|display-A": SpaceDisplayLayout(
        spaceUUID: "oldest", displayUUID: "display-A",
        apps: [
          "com.googlecode.iterm2": olderITermFrame,
          "com.apple.Safari": safariFrame,
        ],
        capturedAt: Date(timeIntervalSince1970: 100)),
      "newest|display-A": SpaceDisplayLayout(
        spaceUUID: "newest", displayUUID: "display-A",
        apps: [
          "com.googlecode.iterm2": newerITermFrame,
          "com.example.unrelated": unrelatedFrame,
          "com.current": unrelatedCurrentFrame,
        ],
        capturedAt: Date(timeIntervalSince1970: 500)),
      "other|display-B": SpaceDisplayLayout(
        spaceUUID: "other", displayUUID: "display-B",
        apps: ["com.googlecode.iterm2": wrongDisplayFrame],
        capturedAt: Date(timeIntervalSince1970: 300)),
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "windowLayouts")
    let names = makeNameStore(defaults: defaults, names: ["space-new": "Listenly"])
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    _ = store.prepareSpace(
      spaceUUID: "space-new", displayUUID: "display-A",
      legacyWorkspaceID: "workspace-1",
      bundleIDs: ["com.current", "com.googlecode.iterm2", "com.apple.Safari"])
    let apps = store.layout(spaceUUID: "space-new", displayUUID: "display-A")?.apps

    #expect(apps?["com.current"] == currentFrame)
    #expect(apps?["com.googlecode.iterm2"] == newerITermFrame)
    #expect(apps?["com.apple.Safari"] == safariFrame)
    #expect(apps?["com.example.unrelated"] == nil)
  }

  @Test("Legacy workspace associations migrate every app from the known Space UUID")
  func legacyWorkspaceAssociationMigratesKnownUUID() throws {
    let defaults = makeDefaults()
    let configuredFrame = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let manuallyCapturedFrame = WindowFrame(x: 50, y: 60, width: 1200, height: 900)
    let legacy = [
      "space-old|display-A": SpaceDisplayLayout(
        spaceUUID: "space-old", displayUUID: "display-A",
        apps: [
          "com.googlecode.iterm2": configuredFrame,
          "com.example.manually-captured": manuallyCapturedFrame,
        ],
        capturedAt: Date(timeIntervalSince1970: 100))
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "windowLayouts")
    defaults.set(
      ["space-old": "workspace-1"],
      forKey: "workspaceSpaceAssociations")
    let names = makeNameStore(defaults: defaults, names: ["space-new": "Listenly"])
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    _ = store.prepareSpace(
      spaceUUID: "space-new", displayUUID: "display-A",
      legacyWorkspaceID: "workspace-1",
      bundleIDs: ["com.googlecode.iterm2"])
    let apps = store.layout(spaceUUID: "space-new", displayUUID: "display-A")?.apps

    #expect(apps?["com.googlecode.iterm2"] == configuredFrame)
    #expect(apps?["com.example.manually-captured"] == manuallyCapturedFrame)
  }

  @Test("Legacy workspace data migrates into the ordinary named-Space layout")
  func legacyWorkspaceMigratesToLogicalLayout() throws {
    let defaults = makeDefaults()
    let frame = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let manuallyCapturedFrame = WindowFrame(x: 50, y: 60, width: 1200, height: 900)
    let legacy = [
      "workspace-1|display-A": LegacyWorkspaceDisplayLayout(
        workspaceID: "workspace-1", displayUUID: "display-A",
        apps: [
          "com.googlecode.iterm2": frame,
          "com.example.manually-captured": manuallyCapturedFrame,
        ],
        capturedAt: Date(timeIntervalSince1970: 100))
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "workspaceWindowLayouts")
    let names = makeNameStore(defaults: defaults, names: ["space-new": "Listenly"])
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    #expect(
      store.prepareSpace(
        spaceUUID: "space-new", displayUUID: "display-A",
        legacyWorkspaceID: "workspace-1",
        bundleIDs: ["com.googlecode.iterm2"]))
    #expect(
      store.layout(spaceUUID: "space-new", displayUUID: "display-A")?
        .apps["com.googlecode.iterm2"] == frame)
    #expect(
      store.layout(spaceUUID: "space-new", displayUUID: "display-A")?
        .apps["com.example.manually-captured"] == manuallyCapturedFrame)
  }

  @Test("Workspace preparation and ordinary restore share a recreated named layout")
  func workspaceAndOrdinaryRestoreShareLayout() throws {
    let defaults = makeDefaults()
    let frame = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let legacy = [
      "workspace-1|display-A": LegacyWorkspaceDisplayLayout(
        workspaceID: "workspace-1", displayUUID: "display-A",
        apps: ["com.googlecode.iterm2": frame])
    ]
    defaults.set(try JSONEncoder().encode(legacy), forKey: "workspaceWindowLayouts")
    let names = makeNameStore(defaults: defaults, names: ["space-old": "Listenly"])
    let workspaceStore = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-old"]),
      spaceNameStore: names)
    _ = workspaceStore.prepareSpace(
      spaceUUID: "space-old", displayUUID: "display-A",
      legacyWorkspaceID: "workspace-1",
      bundleIDs: ["com.googlecode.iterm2"])

    names.setCustomName(nil, forSpaceUUID: "space-old")
    names.setCustomName("Listenly", forSpaceUUID: "space-new")
    let ordinaryStore = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-new"]),
      spaceNameStore: names)

    #expect(
      ordinaryStore.layout(spaceUUID: "space-new", displayUUID: "display-A")?
        .apps["com.googlecode.iterm2"] == frame)
  }

  @Test("Legacy migration merges the newest frame independently per app")
  func legacyMigrationUsesNewestFramePerApp() throws {
    let defaults = makeDefaults()
    let older = WindowFrame(x: 10, y: 10, width: 100, height: 100)
    let newer = WindowFrame(x: 20, y: 20, width: 200, height: 200)
    let uuidOnly = WindowFrame(x: 30, y: 30, width: 300, height: 300)
    let workspaceOnly = WindowFrame(x: 40, y: 40, width: 400, height: 400)
    let legacyUUID = [
      "space-1|display-A": SpaceDisplayLayout(
        spaceUUID: "space-1", displayUUID: "display-A",
        apps: ["com.shared": older, "com.uuid-only": uuidOnly],
        capturedAt: Date(timeIntervalSince1970: 200))
    ]
    let legacyWorkspace = [
      "workspace-1|display-A": LegacyWorkspaceDisplayLayout(
        workspaceID: "workspace-1", displayUUID: "display-A",
        apps: ["com.shared": newer, "com.workspace-only": workspaceOnly],
        capturedAt: Date(timeIntervalSince1970: 300),
        appCapturedAt: [
          "com.shared": Date(timeIntervalSince1970: 300),
          "com.workspace-only": Date(timeIntervalSince1970: 100),
        ])
    ]
    defaults.set(try JSONEncoder().encode(legacyUUID), forKey: "windowLayouts")
    defaults.set(
      try JSONEncoder().encode(legacyWorkspace), forKey: "workspaceWindowLayouts")
    let names = makeNameStore(defaults: defaults, names: ["space-1": "Listenly"])
    let store = WindowLayoutStore(
      defaults: defaults,
      spaceManager: makeManager(spaceUUIDs: ["space-1"]),
      spaceNameStore: names)

    _ = store.prepareSpace(
      spaceUUID: "space-1", displayUUID: "display-A",
      legacyWorkspaceID: "workspace-1")
    let apps = store.layout(spaceUUID: "space-1", displayUUID: "display-A")?.apps

    #expect(apps?["com.shared"] == newer)
    #expect(apps?["com.uuid-only"] == uuidOnly)
    #expect(apps?["com.workspace-only"] == workspaceOnly)
  }

  @Test("Different displays remain isolated for a named Space")
  func namedLayoutsRemainDisplaySpecific() {
    let (store, _, _) = makeStore(
      names: ["space-1": "Listenly"], currentSpaceUUIDs: ["space-1"])
    let builtIn = WindowFrame(x: 0, y: 0, width: 1800, height: 1130)
    let external = WindowFrame(x: 0, y: 0, width: 2160, height: 1905)
    store.setFrame(
      bundleID: "com.example", frame: builtIn,
      spaceUUID: "space-1", displayUUID: "display-A")
    store.setFrame(
      bundleID: "com.example", frame: external,
      spaceUUID: "space-1", displayUUID: "display-B")

    #expect(
      store.layout(spaceUUID: "space-1", displayUUID: "display-A")?
        .apps["com.example"] == builtIn)
    #expect(
      store.layout(spaceUUID: "space-1", displayUUID: "display-B")?
        .apps["com.example"] == external)
  }

  @Test("clearAll removes logical layouts and legacy migration sources")
  func clearAllRemovesAllLayoutData() {
    let (store, defaults, _) = makeStore()
    store.setFrame(
      bundleID: "com.example", frame: WindowFrame(x: 0, y: 0, width: 100, height: 100),
      spaceUUID: "space-1", displayUUID: "display-A")
    defaults.set(Data("legacy".utf8), forKey: "workspaceWindowLayouts")

    store.clearAll()

    #expect(store.layout(spaceUUID: "space-1", displayUUID: "display-A") == nil)
    #expect(defaults.data(forKey: "windowLayouts") == nil)
    #expect(defaults.data(forKey: "workspaceWindowLayouts") == nil)
    #expect(defaults.dictionary(forKey: "spaceLayoutIdentities") == nil)
  }
}

@Suite("WindowLayoutStore Space Filtering")
struct WindowLayoutStoreSpaceFilteringTests {

  // Regression coverage for issue #3: restore() applied saved frames to every window
  // `kAXWindowsAttribute` returned for an app — including windows living on OTHER
  // spaces — physically yanking them across displays and into whichever space was
  // active there. These tests pin the per-window eligibility logic that restore now
  // consults before touching a window.

  /// Two displays, two spaces: space 100 ("uuid-A") current on display-1,
  /// space 200 ("uuid-B") current on display-2.
  private func makeStore() -> WindowLayoutStore {
    var ds = MockDataSource()
    ds.displaySpaces = [
      [
        "Display Identifier": "display-1",
        "Spaces": [
          ["ManagedSpaceID": 100, "uuid": "uuid-A", "type": 0]
        ],
        "Current Space": ["ManagedSpaceID": 100],
      ],
      [
        "Display Identifier": "display-2",
        "Spaces": [
          ["ManagedSpaceID": 200, "uuid": "uuid-B", "type": 0]
        ],
        "Current Space": ["ManagedSpaceID": 200],
      ],
    ]
    // Window 1 lives on space 100; window 2 on space 200; window 3 is sticky
    // (both spaces); window 4 has no space info at all.
    ds.windowSpaces = [
      1: [100],
      2: [200],
      3: [100, 200],
      4: [],
    ]
    let suite = UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set([String: String](), forKey: "customSpaceNames")
    return WindowLayoutStore(
      defaults: defaults,
      spaceManager: SpaceManager(dataSource: ds),
      spaceNameStore: SpaceNameStore(defaults: defaults))
  }

  @Test("spaceID(forUUID:) resolves a known space UUID to its ManagedSpaceID")
  func resolvesKnownUUID() {
    let store = makeStore()
    #expect(store.spaceID(forUUID: "uuid-A") == 100)
    #expect(store.spaceID(forUUID: "uuid-B") == 200)
  }

  @Test("spaceID(forUUID:) returns nil for an unknown space UUID")
  func unknownUUIDIsNil() {
    let store = makeStore()
    #expect(store.spaceID(forUUID: "uuid-nope") == nil)
  }

  @Test("Window on the target space is eligible for restore")
  func windowOnTargetSpaceEligible() {
    let store = makeStore()
    #expect(store.windowIsOnSpace(windowID: 1, spaceID: 100))
  }

  @Test("Window on a different space is NOT eligible — the issue #3 regression")
  func windowOnOtherSpaceExcluded() {
    let store = makeStore()
    // Window 2 lives on space 200. Restoring space 100's layout must not touch it.
    // (Pre-fix, restore had no per-window space check and moved it anyway.)
    #expect(!store.windowIsOnSpace(windowID: 2, spaceID: 100))
  }

  @Test("Sticky window spanning multiple spaces is eligible on any of them")
  func stickyWindowEligible() {
    let store = makeStore()
    #expect(store.windowIsOnSpace(windowID: 3, spaceID: 100))
    #expect(store.windowIsOnSpace(windowID: 3, spaceID: 200))
  }

  @Test("Window with no space info is NOT eligible — skip is the safe default")
  func unknownWindowExcluded() {
    let store = makeStore()
    #expect(!store.windowIsOnSpace(windowID: 4, spaceID: 100))
  }

  @Test("Window absent from the space map entirely is NOT eligible")
  func unmappedWindowExcluded() {
    let store = makeStore()
    #expect(!store.windowIsOnSpace(windowID: 999, spaceID: 100))
  }
}

@Suite("WindowFrame")
struct WindowFrameTests {
  @Test("Codable round-trip preserves values")
  func codableRoundTrip() throws {
    let frame = WindowFrame(x: 12.5, y: 34.0, width: 800.5, height: 600.25)
    let data = try JSONEncoder().encode(frame)
    let decoded = try JSONDecoder().decode(WindowFrame.self, from: data)
    #expect(decoded == frame)
  }

  @Test("Equatable")
  func equatable() {
    let a = WindowFrame(x: 0, y: 0, width: 100, height: 100)
    let b = WindowFrame(x: 0, y: 0, width: 100, height: 100)
    let c = WindowFrame(x: 1, y: 0, width: 100, height: 100)
    #expect(a == b)
    #expect(a != c)
  }
}
