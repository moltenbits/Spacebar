import AppKit
import Foundation

struct WorkspaceLaunchRequest: Equatable {
  let steps: [WorkspaceLauncherAction]
  let bundleID: String
}

struct WorkspaceLaunchServicesRequest: Equatable {
  let bundleID: String
  let target: URL?
  let arguments: [String]
  let environment: [String: String]
  let createsNewApplicationInstance: Bool
}

/// Owns every workspace launcher execution path. `WorkspaceRestorer` decides
/// when to launch; this type decides how each configured launch mechanism runs.
struct WorkspaceLauncherExecutor {
  typealias ProcessRunner = (URL, [String], Bool) throws -> Void
  typealias LaunchServicesOpener = (WorkspaceLaunchServicesRequest) throws -> Void

  static let live = WorkspaceLauncherExecutor(
    runProcess: runProcess,
    openWithLaunchServices: LaunchServicesWorkspaceOpener.open)

  let runProcess: ProcessRunner
  let openWithLaunchServices: LaunchServicesOpener

  func execute(_ request: WorkspaceLaunchRequest) throws {
    guard !request.steps.isEmpty else {
      throw WorkspaceLauncherError.emptyComposition
    }
    for step in request.steps {
      switch step {
      case .shell(let command):
        try runProcess(
          URL(fileURLWithPath: "/bin/zsh"), ["-c", command], false)
      case .appleScript(let source):
        try runProcess(
          URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", source], true)
      case .openApplication(let applicationName):
        try runProcess(
          URL(fileURLWithPath: "/usr/bin/open"), ["-a", applicationName], true)
      case .launchServices(let configuration):
        guard !request.bundleID.isEmpty else {
          throw WorkspaceLauncherError.missingLaunchServicesBundleID
        }
        var environment: [String: String] = [:]
        for variable in configuration.environment {
          let name = variable.name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !name.isEmpty else { continue }
          environment[name] = variable.value
        }
        try openWithLaunchServices(
          WorkspaceLaunchServicesRequest(
            bundleID: request.bundleID,
            target: Self.launchServicesTarget(from: configuration.target),
            arguments: configuration.arguments,
            environment: environment,
            createsNewApplicationInstance: configuration.createsNewApplicationInstance))
      }
    }
  }

  static func launchServicesTarget(from value: String) -> URL? {
    let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return nil }

    if let url = URL(string: target), url.scheme != nil {
      return url
    }

    let path = (target as NSString).expandingTildeInPath
    return URL(fileURLWithPath: path).standardizedFileURL
  }

  static func openConfiguration(
    for request: WorkspaceLaunchServicesRequest
  ) -> NSWorkspace.OpenConfiguration {
    let configuration = NSWorkspace.OpenConfiguration()
    if !request.arguments.isEmpty {
      configuration.arguments = request.arguments
    }
    if !request.environment.isEmpty {
      configuration.environment = request.environment
    }
    if request.createsNewApplicationInstance {
      configuration.createsNewApplicationInstance = true
    }
    return configuration
  }

  private static func runProcess(
    executable: URL,
    arguments: [String],
    waitsForExit: Bool
  ) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments

    guard waitsForExit else {
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
      try process.run()
      return
    }

    let outputPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = outputPipe
    try process.run()

    outputPipe.fileHandleForWriting.closeFile()
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus != 0 else { return }

    let output = String(decoding: outputData, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let type = executable.lastPathComponent == "osascript" ? "applescript" : "open"
    throw WorkspaceLauncherError.processFailed(
      type: type,
      status: process.terminationStatus,
      output: output)
  }
}

private enum LaunchServicesWorkspaceOpener {
  static func open(_ request: WorkspaceLaunchServicesRequest) throws {
    let workspace = NSWorkspace.shared
    guard
      let applicationURL = workspace.urlForApplication(withBundleIdentifier: request.bundleID)
    else {
      throw WorkspaceLauncherError.applicationNotFound(request.bundleID)
    }

    let configuration = WorkspaceLauncherExecutor.openConfiguration(for: request)
    let completion = LaunchServicesCompletion()
    let semaphore = DispatchSemaphore(value: 0)
    let handler: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
      completion.finish(error: error)
      semaphore.signal()
    }

    if let target = request.target {
      workspace.open(
        [target],
        withApplicationAt: applicationURL,
        configuration: configuration,
        completionHandler: handler)
    } else {
      workspace.openApplication(
        at: applicationURL,
        configuration: configuration,
        completionHandler: handler)
    }

    guard semaphore.wait(timeout: .now() + 30) == .success else {
      throw WorkspaceLauncherError.launchServicesTimedOut(request.bundleID)
    }
    if let error = completion.error {
      throw error
    }
  }
}

enum WorkspaceLauncherError: Error, LocalizedError {
  case emptyComposition
  case missingLaunchServicesBundleID
  case applicationNotFound(String)
  case launchServicesTimedOut(String)
  case processFailed(type: String, status: Int32, output: String)

  var errorDescription: String? {
    switch self {
    case .emptyComposition:
      return "Workspace launcher has no configured steps"
    case .missingLaunchServicesBundleID:
      return "Launch Services launchers require a bundle ID"
    case .applicationNotFound(let bundleID):
      return "No application is installed for bundle ID \(bundleID)"
    case .launchServicesTimedOut(let bundleID):
      return "Launch Services timed out while opening \(bundleID)"
    case .processFailed(let type, let status, let output):
      let detail = output.isEmpty ? "no error output" : output
      return "\(type) launcher exited with status \(status): \(detail)"
    }
  }
}

private final class LaunchServicesCompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var storedError: Error?

  var error: Error? {
    lock.lock()
    defer { lock.unlock() }
    return storedError
  }

  func finish(error: Error?) {
    lock.lock()
    storedError = error
    lock.unlock()
  }
}
