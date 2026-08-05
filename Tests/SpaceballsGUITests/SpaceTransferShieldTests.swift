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
  @Test("Eject and restore both present an overlay and block input")
  func bothOperationsAreShielded() {
    for operation in [SpaceTransferOperation.eject, .restore] {
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

  @Test("A failed input block never claims mouse interaction is paused")
  func reportsBlockFailureHonestly() {
    let mouseInputBlocker = MouseInputBlockerSpy()
    mouseInputBlocker.canBlock = false
    let overlay = OverlaySpy()
    let shield = SpaceTransferShield(
      mouseInputBlocker: mouseInputBlocker,
      shortcutBlocker: ShortcutBlockerSpy(),
      overlay: overlay)

    shield.begin(operation: .restore, plannedMoves: 1)

    #expect(
      overlay.presentations[0].subtitle == SpaceTransferOperation.restore.unblockedInputSubtitle)
  }

  @Test("Finishing releases input and fades the result overlay")
  func finishReleasesShield() {
    let mouseInputBlocker = MouseInputBlockerSpy()
    let shortcutBlocker = ShortcutBlockerSpy()
    let overlay = OverlaySpy()
    let shield = SpaceTransferShield(
      mouseInputBlocker: mouseInputBlocker,
      shortcutBlocker: shortcutBlocker,
      overlay: overlay)
    shield.begin(operation: .eject, plannedMoves: 1)

    shield.finish(message: "Ejected 1 Space")

    #expect(mouseInputBlocker.endCount == 1)
    #expect(shortcutBlocker.endCount == 1)
    #expect(
      overlay.presentations.last
        == .init(message: "Ejected 1 Space", subtitle: nil, showsSpinner: false))
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
        sourceUserData: 0, now: Date(timeIntervalSinceReferenceDate: 99), deadline: deadline))
    #expect(
      !SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: 0, now: deadline, deadline: deadline))
  }

  @Test("Spaceballs synthetic mouse input always passes through")
  func syntheticInputPassesThrough() {
    #expect(
      !SpaceTransferInputPolicy.shouldSuppressMouseEvent(
        sourceUserData: SpaceTransferInputPolicy.syntheticEventTag,
        now: Date(timeIntervalSinceReferenceDate: 99),
        deadline: Date(timeIntervalSinceReferenceDate: 100)))
  }
}
