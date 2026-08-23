import Foundation
import Testing

@testable import SpaceballsCore

@Suite("Workspace Restoration Layout Integration")
struct WorkspaceRestorerTests {
  private func makeNameStore(_ names: [String: String]) -> SpaceNameStore {
    let suite = "WorkspaceRestorerTests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SpaceNameStore(defaults: defaults)
    for (uuid, name) in names {
      store.setCustomName(name, forSpaceUUID: uuid)
    }
    return store
  }

  private func space(
    id: UInt64, uuid: String, displayUUID: String = "display-A"
  ) -> SpaceInfo {
    SpaceInfo(
      id: id, uuid: uuid, type: .desktop, displayUUID: displayUUID, isCurrent: true)
  }

  @Test("Workspace layout restore runs after missing apps are launched")
  func layoutRestoreRunsAfterLaunch() throws {
    let target = space(id: 101, uuid: "space-1")
    let names = makeNameStore([target.uuid: "Work"])
    var launched = false
    var restoredAfterLaunch = false

    let layoutRestorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 1,
      retryInterval: 0,
      prepare: { workspaceID, spaceUUID, displayUUID, bundleIDs in
        #expect(workspaceID == "workspace-1")
        #expect(spaceUUID == target.uuid)
        #expect(displayUUID == target.displayUUID)
        #expect(bundleIDs == ["com.googlecode.iterm2"])
        return true
      },
      attempt: { _, _, _, _ in
        restoredAfterLaunch = launched
        return WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 1,
          restoredBundleIDs: ["com.googlecode.iterm2"], pendingBundleIDs: [])
      },
      sleep: { _ in })

    let hooks = WorkspaceRestorerHooks(
      createDefaultSpaces: { _, _ in 0 },
      allSpaces: { [target] },
      windowsBySpace: { [:] },
      switchToSpace: { _ in },
      clickDesktop: { _ in },
      executeLauncher: { _, _ in launched = true },
      relocateFocusedWindow: { _, _, _, _ in .onTarget },
      sleep: { _ in })
    let restorer = WorkspaceRestorer(
      spaceNameStore: names,
      windowLayoutRestorer: layoutRestorer,
      hooks: hooks)

    _ = try restorer.restoreSync(
      workspaces: [
        WorkspaceConfigData(
          id: "workspace-1", name: "Work", path: nil,
          launchers: [
            LauncherData(
              label: "Terminal", type: "open", command: "iTerm", appName: "iTerm",
              bundleID: "com.googlecode.iterm2")
          ])
      ],
      defaultNames: ["Work"])

    #expect(launched)
    #expect(restoredAfterLaunch)
  }

  @Test("Existing workspace windows are restored without relaunching")
  func existingWindowsAreRestored() throws {
    let target = space(id: 101, uuid: "space-1")
    let names = makeNameStore([target.uuid: "Work"])
    var switched = false
    var launched = false
    var attempts = 0

    let layoutRestorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 1,
      retryInterval: 0,
      prepare: { _, _, _, bundleIDs in
        #expect(bundleIDs == ["com.googlecode.iterm2"])
        return true
      },
      attempt: { _, _, _, _ in
        attempts += 1
        return WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 1,
          restoredBundleIDs: ["com.googlecode.iterm2"], pendingBundleIDs: [])
      },
      sleep: { _ in })
    let existing = WindowInfo(
      id: 1, ownerName: "iTerm", name: "Work", pid: 100,
      bounds: .zero, spaceIDs: [target.id])
    let hooks = WorkspaceRestorerHooks(
      createDefaultSpaces: { _, _ in 0 },
      allSpaces: { [target] },
      windowsBySpace: { [target.id: [existing]] },
      switchToSpace: { _ in switched = true },
      clickDesktop: { _ in },
      executeLauncher: { _, _ in launched = true },
      relocateFocusedWindow: { _, _, _, _ in .onTarget },
      sleep: { _ in })
    let restorer = WorkspaceRestorer(
      spaceNameStore: names,
      windowLayoutRestorer: layoutRestorer,
      hooks: hooks)

    _ = try restorer.restoreSync(
      workspaces: [
        WorkspaceConfigData(
          id: "workspace-1", name: "Work", path: nil,
          launchers: [
            LauncherData(
              label: "Terminal", type: "open", command: "iTerm", appName: "iTerm",
              bundleID: "com.googlecode.iterm2")
          ])
      ],
      defaultNames: ["Work"])

    #expect(switched)
    #expect(!launched)
    #expect(attempts == 1)
  }

  @Test("A timed-out layout does not prevent the next workspace")
  func timeoutDoesNotPreventNextWorkspace() throws {
    let first = space(id: 101, uuid: "space-1")
    let second = space(id: 202, uuid: "space-2")
    let names = makeNameStore([first.uuid: "First", second.uuid: "Second"])
    var attemptedWorkspaces: [String] = []

    let layoutRestorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 2,
      retryInterval: 0,
      prepare: { _, _, _, _ in true },
      attempt: { workspaceID, _, _, _ in
        attemptedWorkspaces.append(workspaceID)
        return WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 0,
          restoredBundleIDs: [], pendingBundleIDs: ["com.missing.app"])
      },
      sleep: { _ in })
    let hooks = WorkspaceRestorerHooks(
      createDefaultSpaces: { _, _ in 0 },
      allSpaces: { [first, second] },
      windowsBySpace: { [:] },
      switchToSpace: { _ in },
      clickDesktop: { _ in },
      executeLauncher: { _, _ in },
      relocateFocusedWindow: { _, _, _, _ in .onTarget },
      sleep: { _ in })
    let restorer = WorkspaceRestorer(
      spaceNameStore: names,
      windowLayoutRestorer: layoutRestorer,
      hooks: hooks)

    _ = try restorer.restoreSync(
      workspaces: [
        WorkspaceConfigData(
          id: "workspace-1", name: "First", path: nil,
          launchers: [LauncherData(label: "One", type: "open", command: "One")]),
        WorkspaceConfigData(
          id: "workspace-2", name: "Second", path: nil,
          launchers: [LauncherData(label: "Two", type: "open", command: "Two")]),
      ],
      defaultNames: ["First", "Second"])

    #expect(attemptedWorkspaces.filter { $0 == "workspace-1" }.count == 2)
    #expect(attemptedWorkspaces.filter { $0 == "workspace-2" }.count == 2)
  }

  @Test("A launcher that steals Space focus is relocated before the next launcher")
  func launcherFocusStealIsCorrected() throws {
    let targetID: UInt64 = 101
    let otherID: UInt64 = 202
    let targetUUID = "space-work"
    let names = makeNameStore([targetUUID: "Work"])
    var currentSpaceID = otherID
    var switchTargets: [UInt64] = []
    var launches: [String] = []
    var relocations: [(bundleID: String, targetSpaceID: UInt64)] = []
    var towerPlacementAttempts = 0

    let spaces: () -> [SpaceInfo] = {
      [
        SpaceInfo(
          id: targetID, uuid: targetUUID, type: .desktop,
          displayUUID: "display-A", isCurrent: currentSpaceID == targetID),
        SpaceInfo(
          id: otherID, uuid: "space-other", type: .desktop,
          displayUUID: "display-A", isCurrent: currentSpaceID == otherID),
      ]
    }
    let hooks = WorkspaceRestorerHooks(
      createDefaultSpaces: { _, _ in 0 },
      allSpaces: spaces,
      windowsBySpace: { [:] },
      switchToSpace: { target in
        switchTargets.append(target)
        currentSpaceID = target
      },
      clickDesktop: { _ in },
      executeLauncher: { _, command in
        #expect(currentSpaceID == targetID)
        launches.append(command)
      },
      relocateFocusedWindow: { bundleID, target, _, allowsExistingWindow in
        relocations.append((bundleID, target))
        if bundleID == "com.apple.Safari" {
          #expect(!allowsExistingWindow)
          return .onTarget
        }
        #expect(allowsExistingWindow)
        towerPlacementAttempts += 1
        if towerPlacementAttempts == 1 {
          // The command returned before Tower finished activating its reused
          // window on another Space.
          currentSpaceID = otherID
          return .waiting
        }
        return .relocated
      },
      sleep: { _ in })
    let restorer = WorkspaceRestorer(
      spaceNameStore: names,
      windowLayoutRestorer: nil,
      hooks: hooks)

    _ = try restorer.restoreSync(
      workspaces: [
        WorkspaceConfigData(
          id: "workspace-1", name: "Work", path: nil,
          launchers: [
            LauncherData(
              label: "Tower", type: "open", command: "Tower", appName: "Tower",
              bundleID: "com.fournova.Tower3"),
            LauncherData(
              label: "Safari", type: "applescript", command: "Safari", appName: "Safari",
              bundleID: "com.apple.Safari"),
          ])
      ],
      defaultNames: ["Work"])

    #expect(launches == ["Tower", "Safari"])
    #expect(switchTargets == [targetID, targetID])
    #expect(
      relocations.map(\.bundleID) == [
        "com.fournova.Tower3", "com.fournova.Tower3", "com.apple.Safari",
      ])
    #expect(currentSpaceID == targetID)
  }

  @Test("New-window launchers never relocate a pre-existing window")
  func relocationEligibilityProtectsExistingWindows() {
    let preexistingWindowIDs: Set<Int> = [700]

    #expect(
      !WorkspaceRestorer.canRelocateLaunchedWindow(
        windowID: 700,
        preexistingWindowIDs: preexistingWindowIDs,
        allowsExistingWindow: false))
    #expect(
      WorkspaceRestorer.canRelocateLaunchedWindow(
        windowID: 701,
        preexistingWindowIDs: preexistingWindowIDs,
        allowsExistingWindow: false))
    #expect(
      WorkspaceRestorer.canRelocateLaunchedWindow(
        windowID: 700,
        preexistingWindowIDs: preexistingWindowIDs,
        allowsExistingWindow: true))
  }
}
