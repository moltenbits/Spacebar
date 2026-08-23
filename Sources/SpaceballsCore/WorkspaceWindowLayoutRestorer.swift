import Foundation

/// Result of one attempt to apply a saved workspace layout. Bundle IDs remain
/// pending until at least one eligible window for that app is resized.
public struct WorkspaceLayoutRestoreAttempt: Equatable {
  public let hasLayout: Bool
  public let movedWindows: Int
  public let restoredBundleIDs: Set<String>
  public let pendingBundleIDs: Set<String>

  public init(
    hasLayout: Bool,
    movedWindows: Int,
    restoredBundleIDs: Set<String>,
    pendingBundleIDs: Set<String>
  ) {
    self.hasLayout = hasLayout
    self.movedWindows = movedWindows
    self.restoredBundleIDs = restoredBundleIDs
    self.pendingBundleIDs = pendingBundleIDs
  }
}

/// Aggregate result of bounded workspace-window discovery and layout restore.
public struct WorkspaceLayoutRestoreOutcome: Equatable {
  public let hasLayout: Bool
  public let attempts: Int
  public let movedWindows: Int
  public let restoredBundleIDs: Set<String>
  public let pendingBundleIDs: Set<String>

  public init(
    hasLayout: Bool,
    attempts: Int,
    movedWindows: Int,
    restoredBundleIDs: Set<String>,
    pendingBundleIDs: Set<String>
  ) {
    self.hasLayout = hasLayout
    self.attempts = attempts
    self.movedWindows = movedWindows
    self.restoredBundleIDs = restoredBundleIDs
    self.pendingBundleIDs = pendingBundleIDs
  }
}

/// Coordinates stable workspace association with bounded polling for windows
/// created asynchronously by workspace launchers.
public final class WorkspaceWindowLayoutRestorer {
  typealias Prepare = (String, String, String, Set<String>) -> Bool
  typealias Attempt = (String, String, String, Set<String>?) -> WorkspaceLayoutRestoreAttempt

  private let maximumAttempts: Int
  private let retryInterval: TimeInterval
  private let prepareAction: Prepare
  private let attemptAction: Attempt
  private let sleep: (TimeInterval) -> Void

  public convenience init(
    store: WindowLayoutStore,
    maximumAttempts: Int = 12,
    retryInterval: TimeInterval = 0.25
  ) {
    self.init(
      maximumAttempts: maximumAttempts,
      retryInterval: retryInterval,
      prepare: { workspaceID, spaceUUID, displayUUID, bundleIDs in
        Self.onMain {
          store.associateWorkspace(
            id: workspaceID,
            spaceUUID: spaceUUID,
            displayUUID: displayUUID,
            bundleIDs: bundleIDs)
        }
      },
      attempt: { workspaceID, spaceUUID, displayUUID, requestedBundleIDs in
        Self.onMain {
          store.restoreWorkspace(
            workspaceID: workspaceID,
            targetSpaceUUID: spaceUUID,
            displayUUID: displayUUID,
            requestedBundleIDs: requestedBundleIDs)
        }
      },
      sleep: { Thread.sleep(forTimeInterval: $0) })
  }

  init(
    maximumAttempts: Int,
    retryInterval: TimeInterval,
    prepare: @escaping Prepare,
    attempt: @escaping Attempt,
    sleep: @escaping (TimeInterval) -> Void
  ) {
    self.maximumAttempts = max(1, maximumAttempts)
    self.retryInterval = retryInterval
    self.prepareAction = prepare
    self.attemptAction = attempt
    self.sleep = sleep
  }

  /// Associates the workspace with its current backing Space and promotes any
  /// existing Space-keyed layout. Returns whether a workspace layout is ready.
  @discardableResult
  public func prepare(
    workspaceID: String,
    spaceUUID: String,
    displayUUID: String,
    bundleIDs: Set<String>
  ) -> Bool {
    prepareAction(workspaceID, spaceUUID, displayUUID, bundleIDs)
  }

  /// Applies the workspace layout, retrying only apps whose target-Space
  /// windows have not appeared yet.
  @discardableResult
  public func restoreWhenReady(
    workspaceID: String,
    spaceUUID: String,
    displayUUID: String
  ) -> WorkspaceLayoutRestoreOutcome {
    let token = Diagnostics.beginTiming(
      "workspace-layout-restore", "wait-for-windows",
      extras: [
        "workspace": workspaceID,
        "space": spaceUUID,
        "display": displayUUID,
      ])
    var movedWindows = 0
    var restoredBundleIDs: Set<String> = []
    var pendingBundleIDs: Set<String> = []
    var requestedBundleIDs: Set<String>?

    for index in 0..<maximumAttempts {
      let result = attemptAction(
        workspaceID, spaceUUID, displayUUID, requestedBundleIDs)
      let attempts = index + 1

      guard result.hasLayout else {
        let outcome = WorkspaceLayoutRestoreOutcome(
          hasLayout: false,
          attempts: attempts,
          movedWindows: movedWindows,
          restoredBundleIDs: restoredBundleIDs,
          pendingBundleIDs: [])
        Diagnostics.endTiming(token, outcome: "no-layout")
        return outcome
      }

      movedWindows += result.movedWindows
      restoredBundleIDs.formUnion(result.restoredBundleIDs)
      pendingBundleIDs = result.pendingBundleIDs

      if pendingBundleIDs.isEmpty {
        let outcome = WorkspaceLayoutRestoreOutcome(
          hasLayout: true,
          attempts: attempts,
          movedWindows: movedWindows,
          restoredBundleIDs: restoredBundleIDs,
          pendingBundleIDs: [])
        Diagnostics.endTiming(
          token,
          outcome:
            "restored apps=\(restoredBundleIDs.count) windows=\(movedWindows) attempts=\(attempts)")
        return outcome
      }

      requestedBundleIDs = pendingBundleIDs
      if attempts < maximumAttempts {
        sleep(retryInterval)
      }
    }

    let outcome = WorkspaceLayoutRestoreOutcome(
      hasLayout: true,
      attempts: maximumAttempts,
      movedWindows: movedWindows,
      restoredBundleIDs: restoredBundleIDs,
      pendingBundleIDs: pendingBundleIDs)
    Diagnostics.endTiming(
      token,
      outcome:
        "timeout restored=\(restoredBundleIDs.count) pending=\(pendingBundleIDs.sorted().joined(separator: ","))"
    )
    return outcome
  }

  private static func onMain<T>(_ body: () -> T) -> T {
    if Thread.isMainThread {
      return body()
    }
    return DispatchQueue.main.sync(execute: body)
  }
}
