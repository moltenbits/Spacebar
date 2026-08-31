import Foundation
import SpaceballsCore

// MARK: - Launch Type

public typealias LaunchType = WorkspaceLaunchType

extension WorkspaceLaunchType {
  public var label: String {
    switch self {
    case .shell: "Shell command"
    case .applescript: "AppleScript"
    case .open: "Open application"
    case .launchServices: "Launch Services"
    }
  }
}

// MARK: - App Launcher

public struct AppLauncher: Codable, Equatable, Identifiable {
  static let legacyITermCommand = """
    tell application "iTerm"
      set newWindow to (create window with default profile)
      tell current session of newWindow
        write text "cd $PATH"
      end tell
    end tell
    """

  static let shellLaunchingITermCommand = """
    do shell script "/usr/bin/open -g -b com.googlecode.iterm2"
    tell application "iTerm"
      set newWindow to (create window with default profile)
      tell current session of newWindow
        write text "cd $PATH"
      end tell
    end tell
    """

  static let iTermCommand = legacyITermCommand

  static let shellLaunchingSafariCommand = """
    tell application "System Events"
      if not (exists process "Safari") then
        do shell script "open -a Safari"
        delay 1
      end if
      tell process "Safari"
        click menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
      end tell
    end tell
    """

  static let safariCommand = """
    tell application "System Events"
      tell process "Safari"
        click menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
      end tell
    end tell
    """

  static let shellLaunchingSafariProfileCommand = """
    tell application "System Events"
      if not (exists process "Safari") then
        do shell script "open -a Safari"
        delay 1
      end if
      tell process "Safari"
        click menu item "New $PROFILE Window" of menu 1 of menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
      end tell
    end tell
    """

  static let safariProfileCommand = """
    tell application "System Events"
      tell process "Safari"
        click menu item "New $PROFILE Window" of menu 1 of menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
      end tell
    end tell
    """

  public var id: UUID
  public var label: String
  public var type: LaunchType
  public var command: String
  /// The app name to look for in the window list (e.g. "Safari", "iTerm2").
  /// If set, the launcher is skipped when an app with this name already has
  /// a window in the target space. If empty, the launcher always runs.
  public var appName: String
  /// Stable application identity used to match saved window layouts.
  public var bundleID: String

  public init(
    id: UUID = UUID(),
    label: String = "",
    type: LaunchType = .shell,
    appName: String = "",
    bundleID: String = "",
    command: String = ""
  ) {
    self.id = id
    self.label = label
    self.type = type
    self.appName = appName
    self.bundleID = bundleID
    self.command = command
  }

  // Decode with backward compatibility for data saved before appName existed.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    let decodedType = try c.decode(LaunchType.self, forKey: .type)
    let decodedCommand = try c.decode(String.self, forKey: .command)
    appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? ""
    bundleID =
      try c.decodeIfPresent(String.self, forKey: .bundleID)
      ?? Self.knownBundleID(forAppName: appName)
    let migrated = Self.migratedLauncher(
      command: decodedCommand, type: decodedType, bundleID: bundleID)
    type = migrated.type
    command = migrated.command
  }

  private enum CodingKeys: String, CodingKey {
    case id, label, type, command, appName, bundleID
  }

  private static func knownBundleID(forAppName appName: String) -> String {
    switch appName.lowercased() {
    case "iterm", "iterm2": "com.googlecode.iterm2"
    case "intellij idea": "com.jetbrains.intellij"
    case "tower": "com.fournova.Tower3"
    case "safari": "com.apple.Safari"
    default: ""
    }
  }

  private static func migratedLauncher(
    command: String, type: LaunchType, bundleID: String
  ) -> (type: LaunchType, command: String) {
    switch (type, bundleID, command) {
    case (.applescript, "com.googlecode.iterm2", legacyITermCommand),
      (.applescript, "com.googlecode.iterm2", shellLaunchingITermCommand):
      return (.applescript, iTermCommand)
    case (.applescript, "com.apple.Safari", shellLaunchingSafariCommand):
      return (.applescript, safariCommand)
    case (.applescript, "com.apple.Safari", shellLaunchingSafariProfileCommand):
      return (.applescript, safariProfileCommand)
    case (.shell, "com.jetbrains.intellij", "idea \"$PATH\""):
      return (.launchServices, "$PATH")
    case (.shell, "com.fournova.Tower3", "gittower \"$PATH\""):
      return (.launchServices, "$PATH")
    default:
      return (type, command)
    }
  }

  /// Returns the command with workspace variables substituted.
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

// MARK: - Workspace Config

public struct WorkspaceConfig: Codable, Equatable, Identifiable {
  public var id: UUID
  public var name: String
  public var path: String?
  public var launchers: [AppLauncher]

  public init(
    id: UUID = UUID(),
    name: String = "",
    path: String? = nil,
    launchers: [AppLauncher] = []
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.launchers = launchers
  }

  // Backward-compatible decoder — new fields default gracefully
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    path = try c.decodeIfPresent(String.self, forKey: .path)
    launchers = try c.decodeIfPresent([AppLauncher].self, forKey: .launchers) ?? []
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, path, launchers
  }
}

// MARK: - Launcher Templates

public enum LauncherTemplate: String, CaseIterable, Identifiable {
  case iterm
  case intellij
  case tower
  case safari
  case safariProfile
  case genericOpen
  case genericLaunchServices
  case genericAppleScript
  case genericShell

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .iterm: "iTerm"
    case .intellij: "IntelliJ IDEA"
    case .tower: "Tower (Git)"
    case .safari: "Safari"
    case .safariProfile: "Safari (Profile)"
    case .genericOpen: "Open App"
    case .genericLaunchServices: "Launch Services"
    case .genericAppleScript: "AppleScript"
    case .genericShell: "Shell Command"
    }
  }

  public var launcher: AppLauncher {
    switch self {
    case .iterm:
      return AppLauncher(
        label: "",
        type: .applescript,
        appName: "iTerm",
        bundleID: "com.googlecode.iterm2",
        command: AppLauncher.iTermCommand
      )
    case .intellij:
      return AppLauncher(
        label: "",
        type: .launchServices,
        appName: "IntelliJ IDEA",
        bundleID: "com.jetbrains.intellij",
        command: "$PATH"
      )
    case .tower:
      return AppLauncher(
        label: "",
        type: .launchServices,
        appName: "Tower",
        bundleID: "com.fournova.Tower3",
        command: "$PATH"
      )
    case .safari:
      return AppLauncher(
        label: "",
        type: .applescript,
        appName: "Safari",
        bundleID: "com.apple.Safari",
        command: AppLauncher.safariCommand
      )
    case .safariProfile:
      return AppLauncher(
        label: "$NAME",
        type: .applescript,
        appName: "Safari",
        bundleID: "com.apple.Safari",
        command: AppLauncher.safariProfileCommand
      )
    case .genericOpen:
      return AppLauncher(
        label: "App",
        type: .open,
        command: "AppName"
      )
    case .genericLaunchServices:
      return AppLauncher(
        label: "App",
        type: .launchServices,
        command: "$PATH"
      )
    case .genericAppleScript:
      return AppLauncher(
        label: "Script",
        type: .applescript,
        command: "-- Enter AppleScript here"
      )
    case .genericShell:
      return AppLauncher(
        label: "Command",
        type: .shell,
        command: "echo \"$PATH\""
      )
    }
  }
}
