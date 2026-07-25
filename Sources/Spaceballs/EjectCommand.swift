import ArgumentParser
import SpaceballsCore

struct EjectCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "eject",
    abstract: "Move all non-default Spaces to the built-in display before disconnecting"
  )

  func run() throws {
    let manager = SpaceManager()
    let summary = try manager.ejectSpaces(
      spaceNameStore: SpaceNameStore(), ejectStore: EjectStore())

    if summary.ejected.isEmpty && summary.failed.isEmpty {
      print("Nothing to eject.")
      return
    }
    print("Ejected \(summary.ejected.count) space(s) to the built-in display.")
    if !summary.failed.isEmpty {
      print("Failed to move \(summary.failed.count) space(s).")
      throw ExitCode.failure
    }
  }
}

struct RestoreCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "restore",
    abstract: "Move previously ejected Spaces back to their original displays"
  )

  func run() throws {
    let manager = SpaceManager()
    let summary = try manager.restoreEjectedSpaces(ejectStore: EjectStore())

    if summary.restored.isEmpty && summary.waiting.isEmpty {
      print("Nothing to restore.")
      return
    }
    if !summary.restored.isEmpty {
      print("Restored \(summary.restored.count) space(s) to their original displays.")
    }
    if !summary.waiting.isEmpty {
      print("\(summary.waiting.count) space(s) still waiting on a disconnected display.")
    }
  }
}
