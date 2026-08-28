import AppKit
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
enum WorkspaceLauncherPlacement: Equatable {
  case waiting
  case onTarget
  case relocated
}

struct WorkspaceLauncherWindow: Equatable {
  let id: Int
  let spaceIDs: [UInt64]
}

struct WorkspaceRestorerHooks {
  var createDefaultSpaces: ([String], SpaceNameStoring) throws -> Int
  var allSpaces: () -> [SpaceInfo]
  var windowsBySpace: () -> [UInt64: [WindowInfo]]
  var launcherWindows: (String) -> [WorkspaceLauncherWindow] = { _ in [] }
  var switchToSpace: (UInt64) throws -> Void
  var clickDesktop: (UInt64) -> Void
  var executeLauncher: (String, String) throws -> Void
  var relocateFocusedWindow: (String, UInt64, Set<Int>, Bool) throws -> WorkspaceLauncherPlacement
  var bundleIDForPID: (Int) -> String? = { _ in nil }
  var relocateWindow: (Int, UInt64) throws -> Bool = { _, _ in false }
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
      launcherWindows: { bundleID in
        Self.accessibilityWindows(bundleID: bundleID, spaceManager: spaceManager)
      },
      switchToSpace: { try spaceManager.switchToSpace(id: $0) },
      clickDesktop: { spaceManager.clickDesktopOnDisplay(forSpaceID: $0) },
      executeLauncher: { try Self.executeLauncher(type: $0, command: $1) },
      relocateFocusedWindow: {
        bundleID, targetSpaceID, preexistingWindowIDs, allowsExistingWindow in
        try Self.relocateFocusedWindow(
          bundleID: bundleID,
          targetSpaceID: targetSpaceID,
          preexistingWindowIDs: preexistingWindowIDs,
          allowsExistingWindow: allowsExistingWindow,
          spaceManager: spaceManager)
      },
      bundleIDForPID: { pid in
        ProcessBundleIdentifierResolver.resolve(pid: pid)
      },
      relocateWindow: { windowID, targetSpaceID in
        try spaceManager.moveWindowToSpace(
          windowID: windowID,
          targetSpaceID: targetSpaceID,
          activateAfterMove: false)
      },
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
        try focusTargetSpace(spaceID, forceSwitch: true)
      } catch {
        errors.append((workspace.name, "", "Failed to switch: \(error.localizedDescription)"))
        continue
      }

      // Launch only missing apps
      var focusFailed = false
      for (launcherIndex, launcher) in missingLaunchers.enumerated() {
        var preexistingWindowIDs = Set(
          hooks.windowsBySpace().values.flatMap { $0 }.map(\.id))
        if !launcher.bundleID.isEmpty {
          preexistingWindowIDs.formUnion(
            hooks.launcherWindows(launcher.bundleID).map(\.id))
        }
        let resolved = launcher.resolvedCommand(path: workspace.path, name: workspace.name)
        do {
          try hooks.executeLauncher(launcher.type, resolved)
          appsLaunched += 1
          if launcher.bundleID.isEmpty {
            hooks.sleep(1.0)
          } else {
            try waitForLaunchedWindowPlacement(
              bundleID: launcher.bundleID,
              targetSpaceID: spaceID,
              preexistingWindowIDs: preexistingWindowIDs,
              // Built-in AppleScript templates explicitly create a new
              // window. Shell/open launchers may legitimately reactivate an
              // existing project window (Tower and IntelliJ do this).
              allowsExistingWindow: launcher.type != "applescript")
          }
        } catch {
          errors.append(
            (
              workspace.name, launcher.appName.isEmpty ? launcher.type : launcher.appName,
              error.localizedDescription
            ))
        }

        guard launcherIndex < missingLaunchers.count - 1 else { continue }
        do {
          try focusTargetSpace(spaceID, forceSwitch: false)
        } catch {
          errors.append((workspace.name, "", "Failed to refocus: \(error.localizedDescription)"))
          focusFailed = true
          break
        }
      }
      if focusFailed { continue }

      // Launching or activating an already-running app can switch macOS back
      // to that app's existing Space. Return to the workspace before applying
      // its layout, even after the final launcher.
      if !missingLaunchers.isEmpty {
        do {
          try focusTargetSpace(spaceID, forceSwitch: false)
        } catch {
          errors.append((workspace.name, "", "Failed to refocus: \(error.localizedDescription)"))
          continue
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

  private func focusTargetSpace(_ spaceID: UInt64, forceSwitch: Bool) throws {
    let isCurrent = hooks.allSpaces().contains { $0.id == spaceID && $0.isCurrent }
    if forceSwitch || !isCurrent {
      if !forceSwitch {
        Diagnostics.log(
          "workspace-restore", "launcher changed active Space; refocusing space=\(spaceID)")
      }
      try hooks.switchToSpace(spaceID)
      hooks.sleep(2.0)  // Let focus and any fallback transition settle
    }
    hooks.clickDesktop(spaceID)
    hooks.sleep(0.5)
  }

  private func waitForLaunchedWindowPlacement(
    bundleID: String,
    targetSpaceID: UInt64,
    preexistingWindowIDs: Set<Int>,
    allowsExistingWindow: Bool
  ) throws {
    let maximumAttempts = 12
    for attempt in 0..<maximumAttempts {
      var newWindows = hooks.launcherWindows(bundleID).filter {
        !preexistingWindowIDs.contains($0.id)
      }
      let inventoryWindows = Self.newLauncherWindows(
        in: hooks.windowsBySpace(),
        bundleID: bundleID,
        preexistingWindowIDs: preexistingWindowIDs,
        bundleIDForPID: hooks.bundleIDForPID
      )
      .map { WorkspaceLauncherWindow(id: $0.id, spaceIDs: $0.spaceIDs) }
      let accessibilityWindowIDs = Set(newWindows.map(\.id))
      newWindows.append(
        contentsOf: inventoryWindows.filter {
          !accessibilityWindowIDs.contains($0.id)
        })
      newWindows.sort { $0.id < $1.id }
      if !newWindows.isEmpty {
        for window in newWindows where !window.spaceIDs.contains(targetSpaceID) {
          Diagnostics.log(
            "workspace-restore",
            "relocating discovered launcher window=\(window.id) to space=\(targetSpaceID)",
            app: bundleID)
          let moved = try hooks.relocateWindow(window.id, targetSpaceID)
          guard moved else {
            throw WorkspaceRestorerError.windowRelocationFailed(
              windowID: window.id, targetSpaceID: targetSpaceID)
          }
        }
        return
      }

      switch try hooks.relocateFocusedWindow(
        bundleID, targetSpaceID, preexistingWindowIDs, allowsExistingWindow)
      {
      case .onTarget, .relocated:
        return
      case .waiting:
        if attempt < maximumAttempts - 1 {
          hooks.sleep(0.25)
        }
      }
    }
    Diagnostics.log(
      "workspace-restore",
      "launcher window placement unresolved after \(maximumAttempts) attempts",
      app: bundleID)
  }

  static func newLauncherWindows(
    in windowsBySpace: [UInt64: [WindowInfo]],
    bundleID: String,
    preexistingWindowIDs: Set<Int>,
    bundleIDForPID: (Int) -> String?
  ) -> [WindowInfo] {
    var windowsByID: [Int: WindowInfo] = [:]
    for window in windowsBySpace.values.joined()
    where !preexistingWindowIDs.contains(window.id)
      && bundleIDForPID(window.pid) == bundleID
    {
      windowsByID[window.id] = window
    }
    return windowsByID.values.sorted { $0.id < $1.id }
  }

  private static func accessibilityWindows(
    bundleID: String,
    spaceManager: SpaceManager
  ) -> [WorkspaceLauncherWindow] {
    var windowsByID: [Int: WorkspaceLauncherWindow] = [:]

    for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      var windowsRef: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(
          appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
        let windows = windowsRef as? [AXUIElement]
      else { continue }

      for window in windows {
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success else { continue }
        let id = Int(windowID)
        windowsByID[id] = WorkspaceLauncherWindow(
          id: id,
          spaceIDs: spaceManager.spaceIDs(forWindowID: id))
      }
    }

    return windowsByID.values.sorted { $0.id < $1.id }
  }

  private static func relocateFocusedWindow(
    bundleID: String,
    targetSpaceID: UInt64,
    preexistingWindowIDs: Set<Int>,
    allowsExistingWindow: Bool,
    spaceManager: SpaceManager
  ) throws -> WorkspaceLauncherPlacement {
    guard let focused = WindowResizer.focusedWindowID() else {
      Diagnostics.log(
        "workspace-restore", "launcher has no resolvable focused window", app: bundleID)
      return .waiting
    }
    let focusedBundleID = ProcessBundleIdentifierResolver.resolve(pid: Int(focused.pid)) ?? ""
    guard focusedBundleID == bundleID else {
      Diagnostics.log(
        "workspace-restore",
        "launcher focus belongs to \(focusedBundleID.isEmpty ? "unknown app" : focusedBundleID)",
        app: bundleID)
      return .waiting
    }

    let windowID = Int(focused.windowID)
    guard
      canRelocateLaunchedWindow(
        windowID: windowID,
        preexistingWindowIDs: preexistingWindowIDs,
        allowsExistingWindow: allowsExistingWindow)
    else {
      Diagnostics.log(
        "workspace-restore",
        "waiting for a new launcher window; focused window=\(windowID) predates launch",
        app: bundleID)
      return .waiting
    }
    guard !spaceManager.spaceIDs(forWindowID: windowID).contains(targetSpaceID) else {
      return .onTarget
    }
    Diagnostics.log(
      "workspace-restore",
      "relocating focused launcher window=\(windowID) to space=\(targetSpaceID)",
      app: bundleID)
    let moved = try spaceManager.moveWindowToSpace(
      windowID: windowID,
      targetSpaceID: targetSpaceID,
      activateAfterMove: false)
    guard moved else {
      throw WorkspaceRestorerError.windowRelocationFailed(
        windowID: windowID, targetSpaceID: targetSpaceID)
    }
    return .relocated
  }

  static func canRelocateLaunchedWindow(
    windowID: Int,
    preexistingWindowIDs: Set<Int>,
    allowsExistingWindow: Bool
  ) -> Bool {
    allowsExistingWindow || !preexistingWindowIDs.contains(windowID)
  }

  static func executeLauncher(type: String, command: String) throws {
    let process = Process()
    var outputPipe: Pipe?
    var waitsForExit = false

    switch type {
    case "shell":
      process.executableURL = URL(fileURLWithPath: "/bin/zsh")
      process.arguments = ["-c", command]
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
    case "applescript":
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", command]
      waitsForExit = true
    case "open":
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-a", command]
      waitsForExit = true
    default:
      throw WorkspaceRestorerError.unknownLaunchType(type)
    }

    if waitsForExit {
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      outputPipe = pipe
    }

    try process.run()
    guard let outputPipe else {
      // Shell launchers may intentionally remain alive for the lifetime of the
      // launched app, so they stay fire-and-forget.
      return
    }

    outputPipe.fileHandleForWriting.closeFile()
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus != 0 else { return }

    let output = String(decoding: outputData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    throw WorkspaceRestorerError.launcherFailed(
      type: type,
      status: process.terminationStatus,
      output: output)
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
  case launcherFailed(type: String, status: Int32, output: String)
  case windowRelocationFailed(windowID: Int, targetSpaceID: UInt64)

  public var errorDescription: String? {
    switch self {
    case .unknownLaunchType(let type):
      return "Unknown launch type: \(type)"
    case .launcherFailed(let type, let status, let output):
      let detail = output.isEmpty ? "no error output" : output
      return "\(type) launcher exited with status \(status): \(detail)"
    case .windowRelocationFailed(let windowID, let targetSpaceID):
      return "Failed to move window \(windowID) to Space \(targetSpaceID)"
    }
  }
}
