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
}
