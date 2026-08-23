import Foundation
import Testing

@testable import SpaceballsCore

@Suite("Workspace Window Layout Restoration")
struct WorkspaceWindowLayoutRestorerTests {
  @Test("Delayed windows are retried and restored")
  func delayedWindowIsRetried() {
    var attempts = 0
    var sleeps = 0
    let restorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 3,
      retryInterval: 0.25,
      prepare: { _, _, _, _ in true },
      attempt: { _, _, _, requestedBundleIDs in
        attempts += 1
        if attempts == 1 {
          #expect(requestedBundleIDs == nil)
          return WorkspaceLayoutRestoreAttempt(
            hasLayout: true, movedWindows: 0,
            restoredBundleIDs: [], pendingBundleIDs: ["com.googlecode.iterm2"])
        }
        #expect(requestedBundleIDs == ["com.googlecode.iterm2"])
        return WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 1,
          restoredBundleIDs: ["com.googlecode.iterm2"], pendingBundleIDs: [])
      },
      sleep: { interval in
        #expect(interval == 0.25)
        sleeps += 1
      })

    #expect(
      restorer.prepare(
        workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A",
        bundleIDs: ["com.googlecode.iterm2"]))
    let outcome = restorer.restoreWhenReady(
      workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A")

    #expect(outcome.attempts == 2)
    #expect(outcome.movedWindows == 1)
    #expect(outcome.restoredBundleIDs == ["com.googlecode.iterm2"])
    #expect(outcome.pendingBundleIDs.isEmpty)
    #expect(sleeps == 1)
  }

  @Test("Multiple apps accumulate while retries target only pending apps")
  func multipleAppsAccumulate() {
    var requested: [Set<String>?] = []
    let restorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 3,
      retryInterval: 0,
      prepare: { _, _, _, _ in true },
      attempt: { _, _, _, bundleIDs in
        requested.append(bundleIDs)
        if requested.count == 1 {
          return WorkspaceLayoutRestoreAttempt(
            hasLayout: true, movedWindows: 1,
            restoredBundleIDs: ["com.apple.Safari"],
            pendingBundleIDs: ["com.googlecode.iterm2"])
        }
        return WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 1,
          restoredBundleIDs: ["com.googlecode.iterm2"], pendingBundleIDs: [])
      },
      sleep: { _ in })

    let outcome = restorer.restoreWhenReady(
      workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A")

    #expect(requested.count == 2)
    #expect(requested[0] == nil)
    #expect(requested[1] == ["com.googlecode.iterm2"])
    #expect(outcome.movedWindows == 2)
    #expect(
      outcome.restoredBundleIDs == ["com.apple.Safari", "com.googlecode.iterm2"])
  }

  @Test("Missing layout returns immediately")
  func missingLayoutReturnsImmediately() {
    var sleeps = 0
    let restorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 3,
      retryInterval: 0.25,
      prepare: { _, _, _, _ in false },
      attempt: { _, _, _, _ in
        WorkspaceLayoutRestoreAttempt(
          hasLayout: false, movedWindows: 0,
          restoredBundleIDs: [], pendingBundleIDs: [])
      },
      sleep: { _ in sleeps += 1 })

    #expect(
      !restorer.prepare(
        workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A",
        bundleIDs: []))
    let outcome = restorer.restoreWhenReady(
      workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A")

    #expect(!outcome.hasLayout)
    #expect(outcome.attempts == 1)
    #expect(sleeps == 0)
  }

  @Test("Windows that never appear stop at the bounded attempt count")
  func timeoutIsBounded() {
    var sleeps = 0
    let restorer = WorkspaceWindowLayoutRestorer(
      maximumAttempts: 3,
      retryInterval: 0.25,
      prepare: { _, _, _, _ in true },
      attempt: { _, _, _, _ in
        WorkspaceLayoutRestoreAttempt(
          hasLayout: true, movedWindows: 0,
          restoredBundleIDs: [], pendingBundleIDs: ["com.missing.app"])
      },
      sleep: { _ in sleeps += 1 })

    let outcome = restorer.restoreWhenReady(
      workspaceID: "workspace-1", spaceUUID: "space-1", displayUUID: "display-A")

    #expect(outcome.attempts == 3)
    #expect(outcome.pendingBundleIDs == ["com.missing.app"])
    #expect(sleeps == 2)
  }
}
