import Cocoa
import SpaceballsCore

/// Consumes physical mouse input while Mission Control automation is
/// posting synthetic drags — a stray user mouse move mid-drag yanks the
/// tile off course. Spaceballs's own events carry
/// `SpaceManager.syntheticEventTag` in `eventSourceUserData` and pass
/// through; untagged (physical) mouse events are swallowed.
///
/// Escape hatches, in order of independence:
/// 1. `unblock()` runs in every eject/restore completion path.
/// 2. The callback checks a hard deadline on every event — past it, the tap
///    disarms itself inline even if no completion path ever fired.
/// 3. The signal handlers in KeyInterceptor.swift disable the tap on
///    SIGTERM/SIGINT/SIGHUP.
/// 4. The tap is a mach port owned by this process: any process death,
///    including SIGKILL, releases it and physical input flows again.
///
/// Main-thread only: block/unblock are called on the main queue and the
/// tap's run-loop source is scheduled on the main run loop, so the callback
/// and all state mutation share one thread.
final class MouseInputBlocker {
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  fileprivate var deadline = Date.distantPast

  /// Starts swallowing physical mouse input until `unblock()` or `timeout`
  /// elapses, whichever comes first. Returns false when the tap can't be
  /// created (Accessibility not granted).
  @discardableResult
  func block(for timeout: TimeInterval) -> Bool {
    unblock()
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
      print("MouseInputBlocker: failed to create event tap")
      return false
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    activeMouseBlockerTap = tap
    return true
  }

  func unblock() {
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
}

private func mouseBlockerCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let blocker = Unmanaged<MouseInputBlocker>.fromOpaque(userInfo).takeUnretainedValue()

  // If the system disabled the tap (slow callback), don't fight it.
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    return Unmanaged.passUnretained(event)
  }

  // Hard deadline: even if every completion path failed, the block expires.
  if Date() >= blocker.deadline {
    blocker.disableFromCallback()
    return Unmanaged.passUnretained(event)
  }

  // Spaceballs's own synthetic events pass through.
  if event.getIntegerValueField(.eventSourceUserData) == SpaceManager.syntheticEventTag {
    return Unmanaged.passUnretained(event)
  }

  return nil  // consume physical mouse input
}
