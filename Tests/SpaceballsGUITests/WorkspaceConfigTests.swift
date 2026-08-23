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
