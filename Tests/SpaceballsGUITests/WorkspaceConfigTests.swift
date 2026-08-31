import Foundation
import Testing

@testable import SpaceballsGUILib

@Suite("Workspace Launcher Bundle IDs")
struct WorkspaceConfigTests {
  @Test("Legacy launchers infer known bundle IDs from their app names")
  func legacyLauncherBundleIDMigration() throws {
    let id = UUID()
    let data = Data(
      """
      {
        "id": "\(id.uuidString)",
        "label": "",
        "type": "applescript",
        "command": "launch iTerm",
        "appName": "iTerm"
      }
      """.utf8)

    let launcher = try JSONDecoder().decode(AppLauncher.self, from: data)

    #expect(launcher.bundleID == "com.googlecode.iterm2")
  }

  @Test("Standard launcher templates declare their launch mechanism and application bundle")
  func standardTemplateConfiguration() {
    #expect(LauncherTemplate.iterm.launcher.bundleID == "com.googlecode.iterm2")
    #expect(LauncherTemplate.iterm.launcher.type == .applescript)
    #expect(!LauncherTemplate.iterm.launcher.command.contains("do shell script"))

    #expect(LauncherTemplate.intellij.launcher.bundleID == "com.jetbrains.intellij")
    #expect(LauncherTemplate.intellij.launcher.type == .launchServices)
    #expect(LauncherTemplate.intellij.launcher.command == "$PATH")

    #expect(LauncherTemplate.tower.launcher.bundleID == "com.fournova.Tower3")
    #expect(LauncherTemplate.tower.launcher.type == .launchServices)
    #expect(LauncherTemplate.tower.launcher.command == "$PATH")

    #expect(LauncherTemplate.safari.launcher.bundleID == "com.apple.Safari")
    #expect(LauncherTemplate.safari.launcher.type == .applescript)
    #expect(!LauncherTemplate.safari.launcher.command.contains("do shell script"))

    #expect(LauncherTemplate.safariProfile.launcher.bundleID == "com.apple.Safari")
    #expect(LauncherTemplate.genericOpen.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericShell.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericAppleScript.launcher.type == .applescript)
    #expect(LauncherTemplate.genericAppleScript.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericLaunchServices.launcher.type == .launchServices)
    #expect(LauncherTemplate.genericLaunchServices.launcher.bundleID.isEmpty)
  }

  @Test("Legacy stock iTerm launchers delegate cold launch to Launch Services")
  func legacyITermLauncherLaunchServicesMigration() throws {
    let legacy = AppLauncher(
      type: .applescript,
      appName: "iTerm",
      bundleID: "com.googlecode.iterm2",
      command: """
        tell application "iTerm"
          set newWindow to (create window with default profile)
          tell current session of newWindow
            write text "cd $PATH"
          end tell
        end tell
        """)

    let migrated = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(legacy))

    #expect(!migrated.command.contains("do shell script"))
    #expect(migrated.command.contains("create window with default profile"))
    #expect(migrated.type == .applescript)
  }

  @Test("Current stock iTerm launchers remove their embedded shell launch")
  func currentITermLauncherLaunchServicesMigration() throws {
    let current = AppLauncher(
      type: .applescript,
      appName: "iTerm",
      bundleID: "com.googlecode.iterm2",
      command: """
        do shell script "/usr/bin/open -g -b com.googlecode.iterm2"
        tell application "iTerm"
          set newWindow to (create window with default profile)
          tell current session of newWindow
            write text "cd $PATH"
          end tell
        end tell
        """)

    let migrated = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(current))

    #expect(!migrated.command.contains("do shell script"))
    #expect(migrated.command.contains("create window with default profile"))
  }

  @Test("Custom iTerm AppleScripts are not replaced by the stock migration")
  func customITermLauncherIsNotMigrated() throws {
    let custom = AppLauncher(
      type: .applescript,
      appName: "iTerm",
      bundleID: "com.googlecode.iterm2",
      command: "tell application \"iTerm\" to create tab with default profile")

    let decoded = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(custom))

    #expect(decoded.command == custom.command)
  }

  @Test("Stock project launchers migrate from shell helpers to Launch Services")
  func stockProjectLauncherMigration() throws {
    let intellij = AppLauncher(
      type: .shell,
      appName: "IntelliJ IDEA",
      bundleID: "com.jetbrains.intellij",
      command: "idea \"$PATH\"")
    let tower = AppLauncher(
      type: .shell,
      appName: "Tower",
      bundleID: "com.fournova.Tower3",
      command: "gittower \"$PATH\"")

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let migratedIntelliJ = try decoder.decode(
      AppLauncher.self, from: encoder.encode(intellij))
    let migratedTower = try decoder.decode(
      AppLauncher.self, from: encoder.encode(tower))

    #expect(migratedIntelliJ.type == .launchServices)
    #expect(migratedIntelliJ.command == "$PATH")
    #expect(migratedTower.type == .launchServices)
    #expect(migratedTower.command == "$PATH")
  }

  @Test("Custom project shell launchers are not migrated")
  func customProjectLauncherIsNotMigrated() throws {
    let custom = AppLauncher(
      type: .shell,
      appName: "IntelliJ IDEA",
      bundleID: "com.jetbrains.intellij",
      command: "idea --line 42 \"$PATH\"")

    let decoded = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(custom))

    #expect(decoded == custom)
  }

  @Test("Stock Safari scripts remove their embedded shell launch")
  func stockSafariLauncherMigration() throws {
    let safari = AppLauncher(
      type: .applescript,
      appName: "Safari",
      bundleID: "com.apple.Safari",
      command: """
        tell application "System Events"
          if not (exists process "Safari") then
            do shell script "open -a Safari"
            delay 1
          end if
          tell process "Safari"
            click menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
          end tell
        end tell
        """)
    let safariProfile = AppLauncher(
      label: "$NAME",
      type: .applescript,
      appName: "Safari",
      bundleID: "com.apple.Safari",
      command: """
        tell application "System Events"
          if not (exists process "Safari") then
            do shell script "open -a Safari"
            delay 1
          end if
          tell process "Safari"
            click menu item "New $PROFILE Window" of menu 1 of menu item "New Window" of menu 1 of menu bar item "File" of menu bar 1
          end tell
        end tell
        """)

    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let migratedSafari = try decoder.decode(
      AppLauncher.self, from: encoder.encode(safari))
    let migratedSafariProfile = try decoder.decode(
      AppLauncher.self, from: encoder.encode(safariProfile))

    #expect(!migratedSafari.command.contains("do shell script"))
    #expect(migratedSafari.command.contains("New Window"))
    #expect(!migratedSafariProfile.command.contains("do shell script"))
    #expect(migratedSafariProfile.command.contains("New $PROFILE Window"))
  }

  @Test("Explicit bundle IDs survive encoding and decoding")
  func bundleIDRoundTrip() throws {
    let original = AppLauncher(
      label: "Terminal", type: .open, appName: "Terminal",
      bundleID: "com.apple.Terminal", command: "Terminal")

    let decoded = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
  }
}
