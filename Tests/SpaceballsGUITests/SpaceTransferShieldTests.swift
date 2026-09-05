import Foundation
import SpaceballsGUILib
import Testing

private final class MouseInputBlockerSpy: SpaceTransferMouseInputBlocking {
  var beginTimeouts: [TimeInterval] = []
  var endCount = 0
  var canBlock = true

  func beginSpaceTransferMouseBlock(for timeout: TimeInterval) -> Bool {
    beginTimeouts.append(timeout)
    return canBlock
  }

  func endSpaceTransferMouseBlock() {
    endCount += 1
  }
}

private final class ShortcutBlockerSpy: SpaceTransferShortcutBlocking {
  var beginCount = 0
  var endCount = 0

  func beginSpaceTransferShortcutBlock() {
    beginCount += 1
  }

  func endSpaceTransferShortcutBlock() {
    endCount += 1
  }
}

private final class OverlaySpy: SpaceTransferOverlayPresenting {
  struct Presentation: Equatable {
    let message: String
    let subtitle: String?
    let showsSpinner: Bool
  }

  var presentations: [Presentation] = []
  var fadeDurations: [TimeInterval] = []

  func show(message: String, subtitle: String?, showsSpinner: Bool) {
    presentations.append(
      Presentation(message: message, subtitle: subtitle, showsSpinner: showsSpinner))
  }

  func update(message: String, subtitle: String?, showsSpinner: Bool) {
    presentations.append(
      Presentation(message: message, subtitle: subtitle, showsSpinner: showsSpinner))
  }

  func dismiss(fadingOver duration: TimeInterval) {
    fadeDurations.append(duration)
  }
}

@Suite("Space Transfer Shield")
struct SpaceTransferShieldTests {
  @Test("A late completion after timeout cannot present another result or release input twice")
  func finishAfterTimeoutIsIgnored() {
    let mouseInputBlocker = MouseInputBlockerSpy()
    let shortcutBlocker = ShortcutBlockerSpy()
    let overlay = OverlaySpy()
    let shield = SpaceTransferShield(
      mouseInputBlocker: mouseInputBlocker,
      shortcutBlocker: shortcutBlocker,
      overlay: overlay)
    shield.begin(operation: .workspaceRestore(name: "Work"), plannedMoves: 1)
    shield.finish(message: "Setup timed out")
    shield.finish(message: "Restored workspace")

    #expect(mouseInputBlocker.endCount == 1)
    #expect(shortcutBlocker.endCount == 1)
    #expect(overlay.presentations.count == 2)
    #expect(overlay.presentations.last?.message == "Setup timed out")
    #expect(overlay.fadeDurations == [1.5])
  }

  @Test("Eject, display restore, and workspace setup all present an overlay and block input")
  func bothOperationsAreShielded() {
    for operation in [SpaceTransferOperation.eject, .restore, .workspaceRestore(name: "Work")] {
      let mouseInputBlocker = MouseInputBlockerSpy()
      let shortcutBlocker = ShortcutBlockerSpy()
      let overlay = OverlaySpy()
      let shield = SpaceTransferShield(
        mouseInputBlocker: mouseInputBlocker,
        shortcutBlocker: shortcutBlocker,
        overlay: overlay)

      shield.begin(operation: operation, plannedMoves: 3)

      #expect(mouseInputBlocker.beginTimeouts == [38])
      #expect(shortcutBlocker.beginCount == 1)
      #expect(overlay.presentations.count == 1)
      #expect(overlay.presentations[0].message == operation.progressMessage)
      #expect(overlay.presentations[0].subtitle == operation.blockedInputSubtitle)
      #expect(overlay.presentations[0].showsSpinner)
    }
  }

  @Test("Workspace setup identifies the workspace in its progress message")
  func workspaceProgressMessage() {
    #expect(
      SpaceTransferOperation.workspaceRestore(name: "Work").progressMessage == "Setting up Work…")
  }

  @Test("A failed input block never claims mouse interaction is paused")
  func reportsBlockFailureHonestly() {
    let mouseInputBlocker = MouseInputBlockerSpy()
    mouseInputBlocker.canBlock = false
    let overlay = OverlaySpy()
    let shield = SpaceTransferShield(
      mouseInputBlocker: mouseInputBlocker,
      shortcutBlocker: ShortcutBlockerSpy(),
      overlay: overlay)

    shield.begin(operation: .workspaceRestore(name: "Work"), plannedMoves: 1)

    #expect(
      overlay.presentations[0].subtitle
        == SpaceTransferOperation.workspaceRestore(name: "Work").unblockedInputSubtitle)
  }

  @Test(
    "Success, failure, and timeout all release input and fade the result overlay",
    arguments: ["Restored Work", "Failed to set up Work", "Setup timed out"])
  func finishReleasesShield(message: String) {
    let mouseInputBlocker = MouseInputBlockerSpy()
    let shortcutBlocker = ShortcutBlockerSpy()
    let overlay = OverlaySpy()
    let shield = SpaceTransferShield(
      mouseInputBlocker: mouseInputBlocker,
      shortcutBlocker: shortcutBlocker,
      overlay: overlay)
    shield.begin(operation: .workspaceRestore(name: "Work"), plannedMoves: 1)

    shield.finish(message: message)

    #expect(mouseInputBlocker.endCount == 1)
    #expect(shortcutBlocker.endCount == 1)
    #expect(
      overlay.presentations.last
        == .init(message: message, subtitle: nil, showsSpinner: false))
    #expect(overlay.fadeDurations == [1.5])
  }
}

@Suite("Space Transfer Input Policy")
struct SpaceTransferInputPolicyTests {
  @Test("Physical mouse input is suppressed only before the deadline")
  func physicalInputDeadline() {
    let deadline = Date(timeIntervalSinceReferenceDate: 100)

    #expect(
      SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: 0,
        sourceProcessID: 0,
        currentProcessID: 42,
        now: Date(timeIntervalSinceReferenceDate: 99),
        deadline: deadline))
    #expect(
      !SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: 0,
        sourceProcessID: 0,
        currentProcessID: 42,
        now: deadline,
        deadline: deadline))
  }

  @Test("Only Spaceballs-tagged mouse input from this process passes through")
  func syntheticInputPassesThrough() {
    #expect(
      !SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: SpaceTransferInputPolicy.syntheticEventTag,
        sourceProcessID: 42,
        currentProcessID: 42,
        now: Date(timeIntervalSinceReferenceDate: 99),
        deadline: Date(timeIntervalSinceReferenceDate: 100)))
    #expect(
      SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: SpaceTransferInputPolicy.syntheticEventTag,
        sourceProcessID: 0,
        currentProcessID: 42,
        now: Date(timeIntervalSinceReferenceDate: 99),
        deadline: Date(timeIntervalSinceReferenceDate: 100)))
  }
}
