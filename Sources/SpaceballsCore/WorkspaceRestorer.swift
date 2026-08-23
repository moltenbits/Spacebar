import Foundation

/// Result of a workspace restoration operation.
public struct RestoreSummary {
  public let spacesCreated: Int
  public let appsLaunched: Int
  public let errors: [(workspace: String, launcher: String, error: String)]

  public init(spacesCreated: Int, appsLaunched: Int, errors: [(String, String, String)]) {
    self.spacesCreated = spacesCreated
    self.appsLaunched = appsLaunched
    self.errors = errors
  }
}

/// System operations used by `WorkspaceRestorer`. Keeping the orchestration
/// behind narrow closures makes launch/restore ordering deterministic in tests.
struct WorkspaceRestorerHooks {
  var createDefaultSpaces: ([String], SpaceNameStoring) throws -> Int
  var allSpaces: () -> [SpaceInfo]
  var windowsBySpace: () -> [UInt64: [WindowInfo]]
  var switchToSpace: (UInt64) throws -> Void
  var clickDesktop: (UInt64) -> Void
  var executeLauncher: (String, String) throws -> Void
  var sleep: (TimeInterval) -> Void
}

/// Orchestrates workspace restoration: creates spaces, switches to each,
/// and launches configured apps. Shared between CLI and GUI.
public final class WorkspaceRestorer {
  private let spaceNameStore: SpaceNameStoring
  private let windowLayoutRestorer: WorkspaceWindowLayoutRestorer?
  private let hooks: WorkspaceRestorerHooks

  public convenience init(
    spaceManager: SpaceManager,
    spaceNameStore: SpaceNameStoring,
    windowLayoutRestorer: WorkspaceWindowLayoutRestorer? = nil
  ) {
    let hooks = WorkspaceRestorerHooks(
      createDefaultSpaces: { names, store in
        try spaceManager.createDefaultSpacesSync(
          defaultNames: names, spaceNameStore: store)
      },
      allSpaces: { spaceManager.getAllSpaces() },
      windowsBySpace: { spaceManager.windowsBySpace().1 },
      switchToSpace: { try spaceManager.switchToSpace(id: $0) },
      clickDesktop: { spaceManager.clickDesktopOnDisplay(forSpaceID: $0) },
      executeLauncher: { try Self.executeLauncher(type: $0, command: $1) },
      sleep: { Thread.sleep(forTimeInterval: $0) })
    self.init(
      spaceNameStore: spaceNameStore,
      windowLayoutRestorer: windowLayoutRestorer,
      hooks: hooks)
  }

  init(
    spaceNameStore: SpaceNameStoring,
    windowLayoutRestorer: WorkspaceWindowLayoutRestorer?,
    hooks: WorkspaceRestorerHooks
  ) {
    self.spaceNameStore = spaceNameStore
    self.windowLayoutRestorer = windowLayoutRestorer
    self.hooks = hooks
  }

  /// Synchronously restores workspaces: creates missing spaces, switches to
  /// each one, and launches its configured apps.
  ///
  /// - Parameters:
  ///   - workspaces: Workspace configs to restore.
  ///   - defaultNames: All workspace names (for createDefaultSpaces).
  ///   - progress: Optional callback after each workspace (completed, total, name).
  /// - Returns: Summary of what was done.
  public func restoreSync(
    workspaces: [WorkspaceConfigData],
    defaultNames: [String],
    progress: ((Int, Int, String) -> Void)? = nil
  ) throws -> RestoreSummary {
    // 1. Create any missing spaces
    let spacesCreated = try hooks.createDefaultSpaces(defaultNames, spaceNameStore)

    // Brief pause if spaces were created
    if spacesCreated > 0 {
      hooks.sleep(1.0)
    }

    // 2. Restore each workspace that has launchers
    let workspacesWithLaunchers = workspaces.filter { !$0.launchers.isEmpty }
    var appsLaunched = 0
    var errors: [(String, String, String)] = []

    for (i, workspace) in workspacesWithLaunchers.enumerated() {
      progress?(i, workspacesWithLaunchers.count, workspace.name)

      // Resolve space name to ID
      let spaces = hooks.allSpaces()
      guard let spaceID = spaceNameStore.resolveSpaceID(workspace.name, spaces: spaces) else {
        errors.append((workspace.name, "", "Space not found"))
        continue
      }
      guard let targetSpace = spaces.first(where: { $0.id == spaceID }) else {
        errors.append((workspace.name, "", "Resolved Space is missing from the current snapshot"))
        continue
      }

      // Check which apps are already running in this space
      let windowMap = hooks.windowsBySpace()
      let existingApps = Set(
        (windowMap[spaceID] ?? []).map(\.ownerName)
      )

      // Filter to only launchers whose app isn't already in the space
      let missingLaunchers = workspace.launchers.filter { launcher in
        if launcher.appName.isEmpty { return true }  // No app name → always run
        return !existingApps.contains(launcher.appName)
      }

      // Associate before launching so future Spaceballs resizes update the
      // stable workspace layout even when no prior workspace layout exists.
      let hasWorkspaceLayout =
        windowLayoutRestorer?.prepare(
          workspaceID: workspace.id,
          spaceUUID: targetSpace.uuid,
          displayUUID: targetSpace.displayUUID,
          bundleIDs: Set(workspace.launchers.map(\.bundleID).filter { !$0.isEmpty })) ?? false

      // Existing windows still need an explicit workspace-layout restore.
      guard !missingLaunchers.isEmpty || hasWorkspaceLayout else { continue }

      // Switch to the space and ensure it has keyboard focus.
      // On multi-display, Launch Services opens apps on the display with
      // keyboard focus, so we click on the target display's desktop after
      // switching to ensure apps open on the correct display.
      do {
        try hooks.switchToSpace(spaceID)
        hooks.sleep(2.0)  // Let focus and any fallback transition settle
        hooks.clickDesktop(spaceID)
        hooks.sleep(0.5)
      } catch {
        errors.append((workspace.name, "", "Failed to switch: \(error.localizedDescription)"))
        continue
      }

      // Launch only missing apps
      for launcher in missingLaunchers {
        let resolved = launcher.resolvedCommand(path: workspace.path, name: workspace.name)
        do {
          try hooks.executeLauncher(launcher.type, resolved)
          appsLaunched += 1
          hooks.sleep(1.0)
        } catch {
          errors.append(
            (
              workspace.name, launcher.appName.isEmpty ? launcher.type : launcher.appName,
              error.localizedDescription
            ))
        }
      }

      if hasWorkspaceLayout {
        _ = windowLayoutRestorer?.restoreWhenReady(
          workspaceID: workspace.id,
          spaceUUID: targetSpace.uuid,
          displayUUID: targetSpace.displayUUID)
      }
    }

    progress?(workspacesWithLaunchers.count, workspacesWithLaunchers.count, "Done")

    return RestoreSummary(
      spacesCreated: spacesCreated,
      appsLaunched: appsLaunched,
      errors: errors
    )
  }

  private static func executeLauncher(type: String, command: String) throws {
    let process = Process()
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    switch type {
    case "shell":
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-c", command]
    case "applescript":
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", command]
    case "open":
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", command]
    default:
      throw WorkspaceRestorerError.unknownLaunchType(type)
    }

    try process.run()
    // Don't wait for completion — apps should stay running
  }
}

/// Lightweight data transfer struct so WorkspaceRestorer doesn't depend on
/// SpaceballsGUILib's WorkspaceConfig (which lives in a different module).
public struct WorkspaceConfigData {
  public let id: String
  public let name: String
  public let path: String?
  public let launchers: [LauncherData]

  public init(id: String, name: String, path: String?, launchers: [LauncherData]) {
    self.id = id
    self.name = name
    self.path = path
    self.launchers = launchers
  }
}

public struct LauncherData {
  public let label: String
  public let type: String  // "shell", "applescript", "open"
  public let command: String
  public let appName: String
  public let bundleID: String

  public init(
    label: String,
    type: String,
    command: String,
    appName: String = "",
    bundleID: String = ""
  ) {
    self.label = label
    self.type = type
    self.command = command
    self.appName = appName
    self.bundleID = bundleID
  }

  public func resolvedCommand(path: String?, name: String) -> String {
    var cmd = command
    let expandedPath = (path as NSString?)?.expandingTildeInPath ?? ""
    let resolvedProfile = label.isEmpty ? name : label
    cmd = cmd.replacingOccurrences(of: "$PATH", with: expandedPath)
    cmd = cmd.replacingOccurrences(of: "${PATH}", with: expandedPath)
    cmd = cmd.replacingOccurrences(of: "$NAME", with: name)
    cmd = cmd.replacingOccurrences(of: "${NAME}", with: name)
    cmd = cmd.replacingOccurrences(of: "$PROFILE", with: resolvedProfile)
    cmd = cmd.replacingOccurrences(of: "${LABEL}", with: resolvedProfile)
    return cmd
  }
}

public enum WorkspaceRestorerError: Error, LocalizedError {
  case unknownLaunchType(String)

  public var errorDescription: String? {
    switch self {
    case .unknownLaunchType(let type):
      return "Unknown launch type: \(type)"
    }
  }
}
