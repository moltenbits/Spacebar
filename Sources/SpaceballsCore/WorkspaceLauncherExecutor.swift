import AppKit
import Foundation

public enum WorkspaceLaunchType: String, Codable, CaseIterable, Identifiable, Sendable {
  case shell
  case applescript
  case open
  case launchServices

  public var id: String { rawValue }
}

struct WorkspaceLaunchRequest: Equatable {
  let type: WorkspaceLaunchType
  let command: String
  let bundleID: String
}

/// Owns every workspace launcher execution path. `WorkspaceRestorer` decides
/// when to launch; this type decides how each configured launch mechanism runs.
struct WorkspaceLauncherExecutor {
  typealias ProcessRunner = (URL, [String], Bool) throws -> Void
  typealias LaunchServicesOpener = (String, URL?) throws -> Void

  static let live = WorkspaceLauncherExecutor(
    runProcess: runProcess,
    openWithLaunchServices: LaunchServicesWorkspaceOpener.open)

  let runProcess: ProcessRunner
  let openWithLaunchServices: LaunchServicesOpener

  func execute(_ request: WorkspaceLaunchRequest) throws {
    switch request.type {
    case .shell:
      try runProcess(
        URL(fileURLWithPath: "/bin/zsh"), ["-c", request.command], false)
    case .applescript:
      if !request.bundleID.isEmpty {
        try openWithLaunchServices(request.bundleID, nil)
      }
      try runProcess(
        URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", request.command], true)
    case .open:
      try runProcess(
        URL(fileURLWithPath: "/usr/bin/open"), ["-a", request.command], true)
    case .launchServices:
      guard !request.bundleID.isEmpty else {
        throw WorkspaceLauncherError.missingLaunchServicesBundleID
      }
      try openWithLaunchServices(
        request.bundleID, Self.launchServicesTarget(from: request.command))
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
  static func open(bundleID: String, target: URL?) throws {
    let workspace = NSWorkspace.shared
    guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
      throw WorkspaceLauncherError.applicationNotFound(bundleID)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let completion = LaunchServicesCompletion()
    let semaphore = DispatchSemaphore(value: 0)
    let handler: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
      completion.finish(error: error)
      semaphore.signal()
    }

    if let target {
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
      throw WorkspaceLauncherError.launchServicesTimedOut(bundleID)
    }
    if let error = completion.error {
      throw error
    }
  }
}

enum WorkspaceLauncherError: Error, LocalizedError {
  case missingLaunchServicesBundleID
  case applicationNotFound(String)
  case launchServicesTimedOut(String)
  case processFailed(type: String, status: Int32, output: String)

  var errorDescription: String? {
    switch self {
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
