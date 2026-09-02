import Foundation
import SpaceballsCore
import Testing

@testable import SpaceballsGUILib

@Suite("Workspace Launcher Bundle IDs")
struct WorkspaceConfigTests {
  @Test("Window-specific templates explicitly compose Launch Services and AppleScript")
  func windowSpecificTemplatesAreComposed() {
    let iterm = LauncherTemplate.iterm.launcher
    let safari = LauncherTemplate.safari.launcher
    let safariProfile = LauncherTemplate.safariProfile.launcher

    #expect(iterm.steps.map(\.type) == [.launchServices, .applescript])
    #expect(safari.steps.map(\.type) == [.launchServices, .applescript])
    #expect(safariProfile.steps.map(\.type) == [.launchServices, .applescript])

    guard case .launchServices(let launch) = iterm.steps[0].action,
      case .appleScript(let script) = iterm.steps[1].action
    else {
      Issue.record("Expected iTerm to launch first and configure its window second")
      return
    }
    #expect(launch.target.isEmpty)
    #expect(!launch.activates)
    #expect(script.contains("create window with default profile"))
  }

  @Test("A composed launcher round-trips typed per-step configuration")
  func composedLauncherRoundTrip() throws {
    let original = AppLauncher(
      label: "Configured App",
      appName: "Configured App",
      bundleID: "com.example.configured",
      steps: [
        WorkspaceLauncherStep(
          action: .launchServices(
            WorkspaceLaunchServicesConfiguration(
              target: "$PATH",
              arguments: ["--workspace", "$NAME"],
              environment: [
                WorkspaceEnvironmentVariable(name: "PROJECT_ROOT", value: "$PATH")
              ],
              createsNewApplicationInstance: true,
              activates: false))),
        WorkspaceLauncherStep(
          action: .appleScript("tell application \"Configured App\" to activate")),
      ])

    let decoded = try JSONDecoder().decode(
      AppLauncher.self, from: JSONEncoder().encode(original))

    #expect(decoded == original)
  }

  @Test("Launch Services configurations decoded without activation preserve the old default")
  func launchServicesActivationDecodeDefault() throws {
    let data = Data(
      """
      {
        "target": "$PATH",
        "arguments": [],
        "environment": [],
        "createsNewApplicationInstance": false
      }
      """.utf8)

    let configuration = try JSONDecoder().decode(
      WorkspaceLaunchServicesConfiguration.self, from: data)

    #expect(configuration.activates)
  }

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

    #expect(LauncherTemplate.intellij.launcher.bundleID == "com.jetbrains.intellij")
    #expect(LauncherTemplate.intellij.launcher.steps.map(\.type) == [.launchServices])
    guard
      case .launchServices(let intelliJConfiguration) =
        LauncherTemplate.intellij.launcher.steps[0].action
    else {
      Issue.record("Expected the IntelliJ Launch Services configuration")
      return
    }
    #expect(intelliJConfiguration.target == "$PATH")
    #expect(intelliJConfiguration.activates)

    #expect(LauncherTemplate.tower.launcher.bundleID == "com.fournova.Tower3")
    #expect(LauncherTemplate.tower.launcher.steps.map(\.type) == [.launchServices])
    guard
      case .launchServices(let towerConfiguration) =
        LauncherTemplate.tower.launcher.steps[0].action
    else {
      Issue.record("Expected the Tower Launch Services configuration")
      return
    }
    #expect(towerConfiguration.activates)

    #expect(LauncherTemplate.safari.launcher.bundleID == "com.apple.Safari")

    #expect(LauncherTemplate.safariProfile.launcher.bundleID == "com.apple.Safari")
    guard
      case .launchServices(let safariConfiguration) =
        LauncherTemplate.safari.launcher.steps[0].action,
      case .launchServices(let safariProfileConfiguration) =
        LauncherTemplate.safariProfile.launcher.steps[0].action
    else {
      Issue.record("Expected the Safari Launch Services configurations")
      return
    }
    #expect(!safariConfiguration.activates)
    #expect(!safariProfileConfiguration.activates)
    #expect(LauncherTemplate.genericOpen.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericShell.launcher.bundleID.isEmpty)
    #expect(LauncherTemplate.genericAppleScript.launcher.steps.map(\.type) == [.applescript])
    #expect(LauncherTemplate.genericAppleScript.launcher.bundleID.isEmpty)
    #expect(
      LauncherTemplate.genericLaunchServices.launcher.steps.map(\.type) == [.launchServices])
    #expect(LauncherTemplate.genericLaunchServices.launcher.bundleID.isEmpty)
    guard
      case .launchServices(let genericConfiguration) =
        LauncherTemplate.genericLaunchServices.launcher.steps[0].action
    else {
      Issue.record("Expected the generic Launch Services configuration")
      return
    }
    #expect(genericConfiguration.activates)
  }

  @Test("Legacy stock iTerm launchers migrate to an explicit composed pipeline")
  func legacyITermLauncherLaunchServicesMigration() throws {
    let migrated = try decodeLegacyLauncher(
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

    #expect(migrated.steps.map(\.type) == [.launchServices, .applescript])
    guard case .launchServices(let configuration) = migrated.steps[0].action,
      case .appleScript(let script) = migrated.steps[1].action
    else {
      Issue.record("Expected the migrated iTerm configuration step")
      return
    }
    #expect(!configuration.activates)
    #expect(!script.contains("do shell script"))
    #expect(script.contains("create window with default profile"))
  }

  @Test("Current stock iTerm launchers remove their embedded shell launch")
  func currentITermLauncherLaunchServicesMigration() throws {
    let migrated = try decodeLegacyLauncher(
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

    #expect(migrated.steps.map(\.type) == [.launchServices, .applescript])
    guard case .launchServices(let configuration) = migrated.steps[0].action,
      case .appleScript(let script) = migrated.steps[1].action
    else {
      Issue.record("Expected the migrated iTerm AppleScript")
      return
    }
    #expect(!configuration.activates)
    #expect(!script.contains("do shell script"))
    #expect(script.contains("create window with default profile"))
  }

  @Test("Custom iTerm AppleScripts are not replaced by the stock migration")
  func customITermLauncherIsNotMigrated() throws {
    let decoded = try decodeLegacyLauncher(
      type: .applescript,
      appName: "iTerm",
      bundleID: "com.googlecode.iterm2",
      command: "tell application \"iTerm\" to create tab with default profile")

    #expect(decoded.steps.map(\.type) == [.applescript])
    #expect(
      decoded.steps.first?.action
        == .appleScript("tell application \"iTerm\" to create tab with default profile"))
  }

  @Test("Stock project launchers migrate from shell helpers to Launch Services")
  func stockProjectLauncherMigration() throws {
    let migratedIntelliJ = try decodeLegacyLauncher(
      type: .shell,
      appName: "IntelliJ IDEA",
      bundleID: "com.jetbrains.intellij",
      command: "idea \"$PATH\"")
    let migratedTower = try decodeLegacyLauncher(
      type: .shell,
      appName: "Tower",
      bundleID: "com.fournova.Tower3",
      command: "gittower \"$PATH\"")

    #expect(migratedIntelliJ.steps.map(\.type) == [.launchServices])
    #expect(migratedTower.steps.map(\.type) == [.launchServices])
    guard case .launchServices(let configuration) = migratedIntelliJ.steps[0].action,
      case .launchServices(let towerConfiguration) = migratedTower.steps[0].action
    else {
      Issue.record("Expected migrated IntelliJ Launch Services configuration")
      return
    }
    #expect(configuration.target == "$PATH")
    #expect(configuration.activates)
    #expect(towerConfiguration.activates)
  }

  @Test("Custom project shell launchers are not migrated")
  func customProjectLauncherIsNotMigrated() throws {
    let decoded = try decodeLegacyLauncher(
      type: .shell,
      appName: "IntelliJ IDEA",
      bundleID: "com.jetbrains.intellij",
      command: "idea --line 42 \"$PATH\"")

    #expect(decoded.steps.map(\.type) == [.shell])
    #expect(decoded.steps.first?.action == .shell("idea --line 42 \"$PATH\""))
  }

  @Test("Stock Safari scripts remove their embedded shell launch")
  func stockSafariLauncherMigration() throws {
    let migratedSafari = try decodeLegacyLauncher(
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
    let migratedSafariProfile = try decodeLegacyLauncher(
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
    let migratedCurrentSafari = try decodeLegacyLauncher(
      type: .applescript,
      appName: "Safari",
      bundleID: "com.apple.Safari",
      command: AppLauncher.safariCommand)

    #expect(migratedSafari.steps.map(\.type) == [.launchServices, .applescript])
    #expect(migratedSafariProfile.steps.map(\.type) == [.launchServices, .applescript])
    #expect(migratedCurrentSafari.steps.map(\.type) == [.launchServices, .applescript])
    guard case .launchServices(let safariConfiguration) = migratedSafari.steps[0].action,
      case .launchServices(let profileConfiguration) = migratedSafariProfile.steps[0].action,
      case .launchServices(let currentSafariConfiguration) =
        migratedCurrentSafari.steps[0].action,
      case .appleScript(let safariScript) = migratedSafari.steps[1].action,
      case .appleScript(let profileScript) = migratedSafariProfile.steps[1].action
    else {
      Issue.record("Expected migrated Safari AppleScript steps")
      return
    }
    #expect(!safariConfiguration.activates)
    #expect(!profileConfiguration.activates)
    #expect(!currentSafariConfiguration.activates)
    #expect(!safariScript.contains("do shell script"))
    #expect(safariScript.contains("New Window"))
    #expect(!profileScript.contains("do shell script"))
    #expect(profileScript.contains("New $PROFILE Window"))
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

  private func decodeLegacyLauncher(
    label: String = "",
    type: LaunchType,
    appName: String,
    bundleID: String,
    command: String
  ) throws -> AppLauncher {
    let object: [String: Any] = [
      "id": UUID().uuidString,
      "label": label,
      "type": type.rawValue,
      "command": command,
      "appName": appName,
      "bundleID": bundleID,
    ]
    return try JSONDecoder().decode(
      AppLauncher.self, from: JSONSerialization.data(withJSONObject: object))
  }
}
