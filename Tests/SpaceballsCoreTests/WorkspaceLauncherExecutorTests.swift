import Foundation
import Testing

@testable import SpaceballsCore

@Suite("Workspace Launcher Execution")
struct WorkspaceLauncherExecutorTests {
  @Test("Launch Services opens a file target with the configured bundle")
  func launchServicesOpensTarget() throws {
    var processCalls: [ProcessCall] = []
    var launchCalls: [(bundleID: String, target: URL?)] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processCalls.append(
          ProcessCall(
            executable: executable, arguments: arguments,
            waitsForExit: waitsForExit))
      },
      openWithLaunchServices: { bundleID, target in
        launchCalls.append((bundleID, target))
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .launchServices,
        command: "/Users/example/My Project",
        bundleID: "com.jetbrains.intellij"))

    #expect(processCalls.isEmpty)
    #expect(launchCalls.count == 1)
    #expect(launchCalls.first?.bundleID == "com.jetbrains.intellij")
    #expect(launchCalls.first?.target?.isFileURL == true)
    #expect(launchCalls.first?.target?.path == "/Users/example/My Project")
  }

  @Test("Launch Services launches an app when the target is empty")
  func launchServicesOpensApplication() throws {
    var launchCalls: [(bundleID: String, target: URL?)] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { launchCalls.append(($0, $1)) })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .launchServices, command: "", bundleID: "com.apple.TextEdit"))

    #expect(launchCalls.count == 1)
    #expect(launchCalls.first?.bundleID == "com.apple.TextEdit")
    #expect(launchCalls.first?.target == nil)
  }

  @Test("Launch Services preserves URL targets")
  func launchServicesOpensURL() throws {
    var target: URL?
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { _, openedTarget in target = openedTarget })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .launchServices,
        command: "https://example.com/project",
        bundleID: "com.apple.Safari"))

    #expect(target?.absoluteString == "https://example.com/project")
  }

  @Test("AppleScript launchers use Launch Services before running their script")
  func appleScriptLaunchOrder() throws {
    var events: [String] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        events.append("process")
        #expect(executable.path == "/usr/bin/osascript")
        #expect(arguments == ["-e", "tell application \"iTerm\" to activate"])
        #expect(waitsForExit)
      },
      openWithLaunchServices: { bundleID, target in
        events.append("launch-services")
        #expect(bundleID == "com.googlecode.iterm2")
        #expect(target == nil)
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .applescript,
        command: "tell application \"iTerm\" to activate",
        bundleID: "com.googlecode.iterm2"))

    #expect(events == ["launch-services", "process"])
  }

  @Test("Generic AppleScripts run without requiring an application bundle")
  func genericAppleScript() throws {
    var processCalls: [ProcessCall] = []
    var launched = false
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processCalls.append(
          ProcessCall(
            executable: executable, arguments: arguments,
            waitsForExit: waitsForExit))
      },
      openWithLaunchServices: { _, _ in launched = true })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .applescript, command: "display dialog \"Hello\"", bundleID: ""))

    #expect(!launched)
    #expect(processCalls.count == 1)
    #expect(processCalls.first?.executable.path == "/usr/bin/osascript")
    #expect(processCalls.first?.arguments == ["-e", "display dialog \"Hello\""])
    #expect(processCalls.first?.waitsForExit == true)
  }

  @Test("Shell launchers remain fire-and-forget")
  func shellLauncher() throws {
    var processCall: ProcessCall?
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processCall = ProcessCall(
          executable: executable, arguments: arguments,
          waitsForExit: waitsForExit)
      },
      openWithLaunchServices: { _, _ in
        Issue.record("Shell launchers must not invoke Launch Services")
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        type: .shell, command: "echo hello", bundleID: ""))

    #expect(processCall?.executable.path == "/bin/zsh")
    #expect(processCall?.arguments == ["-c", "echo hello"])
    #expect(processCall?.waitsForExit == false)
  }

  @Test("Legacy open launchers retain their existing behavior")
  func openLauncher() throws {
    var processCall: ProcessCall?
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processCall = ProcessCall(
          executable: executable, arguments: arguments,
          waitsForExit: waitsForExit)
      },
      openWithLaunchServices: { _, _ in
        Issue.record("Legacy open launchers use the open command")
      })

    try executor.execute(
      WorkspaceLaunchRequest(type: .open, command: "Preview", bundleID: ""))

    #expect(processCall?.executable.path == "/usr/bin/open")
    #expect(processCall?.arguments == ["-a", "Preview"])
    #expect(processCall?.waitsForExit == true)
  }

  @Test("Launch Services requires an application bundle")
  func launchServicesRequiresBundleID() {
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { _, _ in })

    #expect(throws: WorkspaceLauncherError.self) {
      try executor.execute(
        WorkspaceLaunchRequest(type: .launchServices, command: "/tmp", bundleID: ""))
    }
  }

  private struct ProcessCall {
    let executable: URL
    let arguments: [String]
    let waitsForExit: Bool
  }
}
