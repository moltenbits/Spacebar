import Foundation
import SpaceballsCore

public enum SpaceTransferOperation: Sendable {
  case eject
  case restore
  case workspaceRestore(name: String)

  public var progressMessage: String {
    switch self {
    case .eject: "Ejecting Spaces…"
    case .restore: "Restoring Spaces…"
    case .workspaceRestore(let name): "Setting up \(name)…"
    }
  }

  public var blockedInputSubtitle: String {
    switch self {
    case .eject: "Mouse interaction paused while ejecting…"
    case .restore, .workspaceRestore: "Mouse interaction paused while restoring…"
    }
  }

  public var unblockedInputSubtitle: String {
    switch self {
    case .eject: "Please avoid mouse interaction while ejecting…"
    case .restore, .workspaceRestore: "Please avoid mouse interaction while restoring…"
    }
  }
}

public protocol SpaceTransferMouseInputBlocking: AnyObject {
  @discardableResult
  func beginSpaceTransferMouseBlock(for timeout: TimeInterval) -> Bool
  func endSpaceTransferMouseBlock()
}

public protocol SpaceTransferShortcutBlocking: AnyObject {
  func beginSpaceTransferShortcutBlock()
  func endSpaceTransferShortcutBlock()
}

public protocol SpaceTransferOverlayPresenting: AnyObject {
  func show(message: String, subtitle: String?, showsSpinner: Bool)
  func update(message: String, subtitle: String?, showsSpinner: Bool)
  func dismiss(fadingOver duration: TimeInterval)
}

/// Owns the user-facing and input-blocking lifecycle shared by eject, display
/// restore, and workspace setup. Keeping these operations on this path prevents the
/// transfer from silently losing the overlay or physical-input protection.
public final class SpaceTransferShield {
  private let mouseInputBlocker: any SpaceTransferMouseInputBlocking
  private let shortcutBlocker: any SpaceTransferShortcutBlocking
  private let overlay: any SpaceTransferOverlayPresenting
  private var isActive = false

  public init(
    mouseInputBlocker: any SpaceTransferMouseInputBlocking,
    shortcutBlocker: any SpaceTransferShortcutBlocking,
    overlay: any SpaceTransferOverlayPresenting
  ) {
    self.mouseInputBlocker = mouseInputBlocker
    self.shortcutBlocker = shortcutBlocker
    self.overlay = overlay
  }

  public func begin(operation: SpaceTransferOperation, plannedMoves: Int) {
    isActive = true
    let timeout = 20.0 + 6.0 * Double(max(0, plannedMoves))
    shortcutBlocker.beginSpaceTransferShortcutBlock()
    let isInputBlocked = mouseInputBlocker.beginSpaceTransferMouseBlock(for: timeout)
    overlay.show(
      message: operation.progressMessage,
      subtitle: isInputBlocked
        ? operation.blockedInputSubtitle
        : operation.unblockedInputSubtitle,
      showsSpinner: true)
  }

  public func finish(message: String) {
    guard isActive else { return }
    isActive = false
    shortcutBlocker.endSpaceTransferShortcutBlock()
    mouseInputBlocker.endSpaceTransferMouseBlock()
    overlay.update(message: message, subtitle: nil, showsSpinner: false)
    overlay.dismiss(fadingOver: 1.5)
  }
}

public enum SpaceTransferInputPolicy {
  public static var syntheticEventTag: Int64 { SpaceManager.syntheticEventTag }

  public static func isBlockActive(now: Date, deadline: Date) -> Bool {
    now < deadline
  }

  public static func shouldSuppressMouseEvent(
    sourceUserData: Int64,
    sourceProcessID: Int64,
    currentProcessID: Int64,
    now: Date,
    deadline: Date
  ) -> Bool {
    guard isBlockActive(now: now, deadline: deadline) else { return false }
    return sourceUserData != syntheticEventTag || sourceProcessID != currentProcessID
  }
}
