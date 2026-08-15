import Foundation

/// Pure planning for closing a Space's windows before the Space itself is
/// closed: decides, per app, whether to quit the whole app or close
/// individual windows.
///
/// An app whose windows ALL live on the doomed Space is quit outright —
/// closing them one by one would leave an empty process still consuming
/// memory (the IntelliJ-per-project case). An app with any window elsewhere
/// (another Space, or sticky on all Spaces) only loses its windows on this
/// Space. Sticky windows are never closed — they survive the Space close on
/// their other Spaces — and their presence keeps the owning app alive.
public enum SpaceCloseWindowPlanner {

  public enum Action: Equatable {
    case quitApp(pid: Int)
    case closeWindow(windowID: Int, pid: Int)
  }

  public struct Plan: Equatable {
    public let actions: [Action]
    /// Window IDs expected to disappear once the actions land — the set to
    /// poll before the Space close proceeds. Anything still alive at the
    /// deadline (an unsaved-changes prompt, a slow quit) is relocated by the
    /// Space close, same as before window-closing existed.
    public let expectedClosedWindowIDs: [Int]
  }

  /// Apps closed window-by-window even when fully on the doomed Space —
  /// quitting Finder only makes launchd relaunch it.
  public static let neverQuitApps: Set<String> = ["Finder"]

  public static func plan(
    windows: [WindowInfo], spaceID: UInt64,
    neverQuitApps: Set<String> = Self.neverQuitApps
  ) -> Plan {
    var pidOrder: [Int] = []
    var windowsByPID: [Int: [WindowInfo]] = [:]
    for window in windows {
      if windowsByPID[window.pid] == nil { pidOrder.append(window.pid) }
      windowsByPID[window.pid, default: []].append(window)
    }

    var actions: [Action] = []
    var expectedClosedWindowIDs: [Int] = []

    for pid in pidOrder {
      let appWindows = windowsByPID[pid]!
      // Trapped = on the doomed space and nowhere else.
      let trapped = appWindows.filter { $0.spaceIDs == [spaceID] }
      guard !trapped.isEmpty else { continue }

      if trapped.count == appWindows.count
        && !neverQuitApps.contains(appWindows[0].ownerName)
      {
        actions.append(.quitApp(pid: pid))
      } else {
        actions.append(contentsOf: trapped.map { .closeWindow(windowID: $0.id, pid: pid) })
      }
      expectedClosedWindowIDs.append(contentsOf: trapped.map(\.id))
    }

    return Plan(actions: actions, expectedClosedWindowIDs: expectedClosedWindowIDs)
  }
}

/// Thread-safe tracker for the close-windows phase: which windows still owe
/// a close confirmation and which quit targets still owe a process exit.
/// The wait polls these precise signals instead of re-enumerating windows —
/// closed windows linger in CGWindowList (and quit victims stay until the
/// process exits), so list-based polling pinned the wait at its timeout.
final class WindowCloseWaitState {
  private let lock = NSLock()
  private var pendingWindows: Set<Int> = []
  private var failedWindows: Set<Int> = []
  private var quitPIDs: Set<Int> = []

  func expectWindow(_ id: Int) {
    lock.lock()
    defer { lock.unlock() }
    pendingWindows.insert(id)
  }

  func expectQuit(pid: Int) {
    lock.lock()
    defer { lock.unlock() }
    quitPIDs.insert(pid)
  }

  /// Marks a window's close attempt finished. A failed press stops the wait
  /// too — the window is not going to close, so there is nothing to wait for
  /// (the space close will relocate it, and the summary reports it).
  func resolveWindow(_ id: Int, closed: Bool) {
    lock.lock()
    defer { lock.unlock() }
    pendingWindows.remove(id)
    if !closed {
      failedWindows.insert(id)
    }
  }

  /// True when no close confirmations are outstanding and every quit
  /// target's process is gone per `isRunning`.
  func allSettled(isRunning: (Int) -> Bool) -> Bool {
    lock.lock()
    let windows = pendingWindows
    let pids = quitPIDs
    lock.unlock()
    return windows.isEmpty && !pids.contains(where: isRunning)
  }

  /// Names everything the space close is about to relocate, for diagnostics.
  func unsettledSummary(isRunning: (Int) -> Bool) -> String {
    lock.lock()
    let windows = pendingWindows
    let failed = failedWindows
    let pids = quitPIDs
    lock.unlock()

    var parts: [String] = []
    parts += windows.sorted().map { "window-\($0)-unconfirmed" }
    parts += failed.sorted().map { "window-\($0)-close-failed" }
    parts += pids.sorted().filter(isRunning).map { "pid-\($0)-still-running" }
    return parts.joined(separator: ",")
  }
}
