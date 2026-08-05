import Cocoa
import SpaceballsCore
import SpaceballsGUILib

/// Consumes physical mouse input while Mission Control automation is
/// posting synthetic drags. Spaceballs's own events carry
/// `SpaceManager.syntheticEventTag` in `eventSourceUserData` and pass
/// through; untagged (physical) mouse events are swallowed.
///
/// This stays separate from the permanent keyboard tap so ordinary mouse
/// movement does not enter Spaceballs's callback outside an eject or restore.
///
/// Escape hatches, in order of independence:
/// 1. `endSpaceTransferMouseBlock()` runs in every transfer completion path.
/// 2. The callback checks a hard deadline on every event and disarms itself
///    after expiry, even if no completion path ever fired.
/// 3. The signal handlers in KeyInterceptor.swift disable the tap on
///    SIGTERM/SIGINT/SIGHUP.
/// 4. The tap is a mach port owned by this process, so process death releases
///    it and physical input flows again.
///
/// Main-thread only: begin/end are called on the main queue and the tap's
/// run-loop source is scheduled on the main run loop, so its callback and all
/// state mutation share one thread.
final class MouseInputBlocker: SpaceTransferMouseInputBlocking {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  fileprivate var deadline = Date.distantPast

  /// Starts swallowing physical mouse input until completion or `timeout`,
  /// whichever comes first. Returns false if Accessibility does not permit a
  /// suppressing event tap.
  @discardableResult
  func beginSpaceTransferMouseBlock(for timeout: TimeInterval) -> Bool {
    endSpaceTransferMouseBlock()
    deadline = Date().addingTimeInterval(timeout)

    let mouseTypes: [CGEventType] = [
      .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
    ]
    let mask = mouseTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: mouseBlockerCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      deadline = .distantPast
      Diagnostics.log("eject", "physical mouse input block unavailable — event tap creation failed")
      return false
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    activeMouseBlockerTap = tap
    guard CGEvent.tapIsEnabled(tap: tap) else {
      Diagnostics.log("eject", "physical mouse input block unavailable — event tap stayed disabled")
      endSpaceTransferMouseBlock()
      return false
    }
    return true
  }

  func endSpaceTransferMouseBlock() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
    activeMouseBlockerTap = nil
    deadline = .distantPast
  }

  fileprivate func disableFromCallback() {
    if let tap = eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
  }

  fileprivate func reenableFromCallback() {
    guard SpaceTransferInputPolicy.isBlockActive(now: Date(), deadline: deadline),
      let tap = eventTap
    else { return }
    CGEvent.tapEnable(tap: tap, enable: true)
  }
}

private func mouseBlockerCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let blocker = Unmanaged<MouseInputBlocker>.fromOpaque(userInfo).takeUnretainedValue()

  // Apple explicitly permits re-enabling a disabled event tap. Keep the
  // short-lived transfer guard active if WindowServer disabled it, while the
  // independent hard deadline still guarantees recovery.
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    blocker.reenableFromCallback()
    return Unmanaged.passUnretained(event)
  }

  if Date() >= blocker.deadline {
    blocker.disableFromCallback()
    return Unmanaged.passUnretained(event)
  }

  return SpaceTransferInputPolicy.shouldSuppressMouseEvent(
    sourceUserData: event.getIntegerValueField(.eventSourceUserData),
    now: Date(),
    deadline: blocker.deadline)
    ? nil
    : Unmanaged.passUnretained(event)
}
