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
    case closeWindow(windowID: Int)
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
        actions.append(contentsOf: trapped.map { .closeWindow(windowID: $0.id) })
      }
      expectedClosedWindowIDs.append(contentsOf: trapped.map(\.id))
    }

    return Plan(actions: actions, expectedClosedWindowIDs: expectedClosedWindowIDs)
  }
}
