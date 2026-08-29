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

  @Test("Standard launcher templates declare the application bundle they restore")
  func standardTemplateBundleIDs() {
    #expect(LauncherTemplate.iterm.launcher.bundleID == "com.googlecode.iterm2")
    #expect(LauncherTemplate.intellij.launcher.bundleID == "com.jetbrains.intellij")
    #expect(LauncherTemplate.tower.launcher.bundleID == "com.fournova.Tower3")
    #expect(LauncherTemplate.safari.launcher.bundleID == "com.apple.Safari")
    #expect(LauncherTemplate.safariProfile.launcher.bundleID == "com.apple.Safari")
    #expect(LauncherTemplate.genericOpen.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericShell.launcher.bundleID.isEmpty)
  }

  @Test("Legacy stock iTerm launchers are migrated to an explicit cold launch")
  func legacyITermLauncherColdLaunchMigration() throws {
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

    #expect(migrated.command.contains("open -g -b com.googlecode.iterm2"))
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
