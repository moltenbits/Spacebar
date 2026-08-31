import Foundation
import Testing

@testable import SpaceballsCore

@Suite("Workspace Launcher Execution")
struct WorkspaceLauncherExecutorTests {
  @Test("Composed launchers execute each typed step in order")
  func composedLauncherOrder() throws {
    var events: [String] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        events.append(executable.lastPathComponent)
        #expect(arguments == ["-e", "tell application \"iTerm\" to activate"])
        #expect(waitsForExit)
      },
      openWithLaunchServices: { request in
        events.append("launch-services")
        #expect(request.bundleID == "com.googlecode.iterm2")
        #expect(request.target == nil)
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [
          .launchServices(WorkspaceLaunchServicesConfiguration()),
          .appleScript("tell application \"iTerm\" to activate"),
        ],
        bundleID: "com.googlecode.iterm2"))

    #expect(events == ["launch-services", "osascript"])
  }

  @Test("Launch Services receives arguments, environment, and instance policy")
  func launchServicesConfiguration() throws {
    var captured: WorkspaceLaunchServicesRequest?
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { captured = $0 })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [
          .launchServices(
            WorkspaceLaunchServicesConfiguration(
              target: "/Users/example/Project",
              arguments: ["--line", "42"],
              environment: [
                WorkspaceEnvironmentVariable(name: "PROJECT", value: "/Users/example/Project"),
                WorkspaceEnvironmentVariable(name: "EMPTY_KEY_IS_IGNORED", value: "first"),
                WorkspaceEnvironmentVariable(name: "", value: "ignored"),
                WorkspaceEnvironmentVariable(name: "EMPTY_KEY_IS_IGNORED", value: "last"),
              ],
              createsNewApplicationInstance: true))
        ],
        bundleID: "com.example.Editor"))

    guard let captured else {
      Issue.record("Expected the Launch Services request")
      return
    }
    #expect(captured.bundleID == "com.example.Editor")
    #expect(captured.target?.path == "/Users/example/Project")
    #expect(captured.arguments == ["--line", "42"])
    #expect(
      captured.environment == [
        "PROJECT": "/Users/example/Project", "EMPTY_KEY_IS_IGNORED": "last",
      ])
    #expect(captured.createsNewApplicationInstance)

    let openConfiguration = WorkspaceLauncherExecutor.openConfiguration(for: captured)
    #expect(openConfiguration.arguments == ["--line", "42"])
    #expect(
      openConfiguration.environment == [
        "PROJECT": "/Users/example/Project", "EMPTY_KEY_IS_IGNORED": "last",
      ])
    #expect(openConfiguration.createsNewApplicationInstance)
  }

  @Test("Launch Services opens a file target with the configured bundle")
  func launchServicesOpensTarget() throws {
    var processCalls: [ProcessCall] = []
    var launchCalls: [WorkspaceLaunchServicesRequest] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processCalls.append(
          ProcessCall(
            executable: executable, arguments: arguments,
            waitsForExit: waitsForExit))
      },
      openWithLaunchServices: { launchCalls.append($0) })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [
          .launchServices(
            WorkspaceLaunchServicesConfiguration(target: "/Users/example/My Project"))
        ],
        bundleID: "com.jetbrains.intellij"))

    #expect(processCalls.isEmpty)
    #expect(launchCalls.count == 1)
    #expect(launchCalls.first?.bundleID == "com.jetbrains.intellij")
    #expect(launchCalls.first?.target?.isFileURL == true)
    #expect(launchCalls.first?.target?.path == "/Users/example/My Project")
  }

  @Test("Launch Services launches an app when the target is empty")
  func launchServicesOpensApplication() throws {
    var launchCalls: [WorkspaceLaunchServicesRequest] = []
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { launchCalls.append($0) })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [.launchServices(WorkspaceLaunchServicesConfiguration())],
        bundleID: "com.apple.TextEdit"))

    #expect(launchCalls.count == 1)
    #expect(launchCalls.first?.bundleID == "com.apple.TextEdit")
    #expect(launchCalls.first?.target == nil)
  }

  @Test("Launch Services preserves URL targets")
  func launchServicesOpensURL() throws {
    var target: URL?
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { target = $0.target })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [
          .launchServices(
            WorkspaceLaunchServicesConfiguration(target: "https://example.com/project"))
        ],
        bundleID: "com.apple.Safari"))

    #expect(target?.absoluteString == "https://example.com/project")
  }

  @Test("AppleScript steps do not hide an implicit application launch")
  func appleScriptHasNoImplicitLaunch() throws {
    var processRan = false
    let executor = WorkspaceLauncherExecutor(
      runProcess: { executable, arguments, waitsForExit in
        processRan = true
        #expect(executable.path == "/usr/bin/osascript")
        #expect(arguments == ["-e", "tell application \"iTerm\" to activate"])
        #expect(waitsForExit)
      },
      openWithLaunchServices: { _ in
        Issue.record("AppleScript must launch an app only through an explicit prior step")
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [.appleScript("tell application \"iTerm\" to activate")],
        bundleID: "com.googlecode.iterm2"))

    #expect(processRan)
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
      openWithLaunchServices: { _ in launched = true })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [.appleScript("display dialog \"Hello\"")], bundleID: ""))

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
      openWithLaunchServices: { _ in
        Issue.record("Shell launchers must not invoke Launch Services")
      })

    try executor.execute(
      WorkspaceLaunchRequest(
        steps: [.shell("echo hello")], bundleID: ""))

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
      openWithLaunchServices: { _ in
        Issue.record("Legacy open launchers use the open command")
      })

    try executor.execute(
      WorkspaceLaunchRequest(steps: [.openApplication("Preview")], bundleID: ""))

    #expect(processCall?.executable.path == "/usr/bin/open")
    #expect(processCall?.arguments == ["-a", "Preview"])
    #expect(processCall?.waitsForExit == true)
  }

  @Test("Launch Services requires an application bundle")
  func launchServicesRequiresBundleID() {
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { _ in })

    #expect(throws: WorkspaceLauncherError.self) {
      try executor.execute(
        WorkspaceLaunchRequest(
          steps: [
            .launchServices(WorkspaceLaunchServicesConfiguration(target: "/tmp"))
          ],
          bundleID: ""))
    }
  }

  @Test("A failed step stops the remaining composition")
  func failedStepStopsComposition() {
    var processRan = false
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in processRan = true },
      openWithLaunchServices: { _ in throw TestError.launchFailed })

    #expect(throws: TestError.self) {
      try executor.execute(
        WorkspaceLaunchRequest(
          steps: [
            .launchServices(WorkspaceLaunchServicesConfiguration()),
            .appleScript("display dialog \"must not run\""),
          ],
          bundleID: "com.example.App"))
    }
    #expect(!processRan)
  }

  @Test("An empty composition is rejected")
  func emptyCompositionIsRejected() {
    let executor = WorkspaceLauncherExecutor(
      runProcess: { _, _, _ in },
      openWithLaunchServices: { _ in })

    #expect(throws: WorkspaceLauncherError.self) {
      try executor.execute(WorkspaceLaunchRequest(steps: [], bundleID: ""))
    }
  }

  private enum TestError: Error {
    case launchFailed
  }

  private struct ProcessCall {
    let executable: URL
    let arguments: [String]
    let waitsForExit: Bool
  }
}
