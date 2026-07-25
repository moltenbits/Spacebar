import Foundation

/// Pure planning for the eject/restore flows — everything decidable from a
/// CGS snapshot, computed up front so the Mission Control session itself
/// only executes a precomputed list of tile drags.
///
/// Moves are grouped per source display in DESCENDING tile-index order:
/// removing a higher-indexed tile never shifts the indices of the tiles
/// still to be dragged, so one CGS snapshot stays valid for the whole batch.
public enum EjectPlanner {

  public struct PreSwitch: Equatable {
    public let displayUUID: String
    /// Index among the display's desktop spaces to switch to before dragging
    /// (MC refuses to drag a display's current space).
    public let toSpaceIndex: Int
    /// ID of that space, for verifying via CGS that the switch landed.
    public let toSpaceID: UInt64

    public init(displayUUID: String, toSpaceIndex: Int, toSpaceID: UInt64) {
      self.displayUUID = displayUUID
      self.toSpaceIndex = toSpaceIndex
      self.toSpaceID = toSpaceID
    }
  }

  public struct Move: Equatable {
    public let spaceID: UInt64
    public let spaceUUID: String
    public let sourceDisplayUUID: String
    /// Index among the source display's desktop spaces (0-based tile index).
    public let sourceIndex: Int
    public let targetDisplayUUID: String
  }

  public struct Plan: Equatable {
    /// Displays whose spaces are all being ejected but which have no Default
    /// Space to stay behind — one must be created (and named) before the
    /// batch runs, after which planning is repeated.
    public let displaysNeedingDefault: [String]
    public let preSwitches: [PreSwitch]
    public let moves: [Move]
  }

  /// Plans moving every non-Default desktop space off every display except
  /// `targetDisplayUUID` (the built-in display).
  public static func plan(
    spaces: [SpaceInfo], targetDisplayUUID: String, names: [String: String]
  ) -> Plan {
    var displaysNeedingDefault: [String] = []
    var preSwitches: [PreSwitch] = []
    var moves: [Move] = []

    for (displayUUID, desktops) in desktopsByDisplay(spaces)
    where displayUUID != targetDisplayUUID {
      let isDefault = { (space: SpaceInfo) in
        names[space.uuid] == SpaceNameStore.defaultSpaceName
      }
      let ejectables = desktops.enumerated().filter { !isDefault($0.element) }
      guard !ejectables.isEmpty else { continue }

      let defaultIndex = desktops.firstIndex(where: isDefault)
      if defaultIndex == nil {
        displaysNeedingDefault.append(displayUUID)
      } else if let defaultIndex, ejectables.contains(where: { $0.element.isCurrent }) {
        preSwitches.append(
          PreSwitch(
            displayUUID: displayUUID, toSpaceIndex: defaultIndex,
            toSpaceID: desktops[defaultIndex].id))
      }

      moves.append(
        contentsOf: ejectables.reversed().map { index, space in
          Move(
            spaceID: space.id, spaceUUID: space.uuid,
            sourceDisplayUUID: displayUUID, sourceIndex: index,
            targetDisplayUUID: targetDisplayUUID)
        })
    }

    return Plan(
      displaysNeedingDefault: displaysNeedingDefault,
      preSwitches: preSwitches, moves: moves)
  }

  /// Desktop spaces grouped per display, preserving CGS enumeration order
  /// (which matches the Mission Control bar's tile order) for both the
  /// displays and the spaces within each.
  static func desktopsByDisplay(_ spaces: [SpaceInfo]) -> [(String, [SpaceInfo])] {
    var order: [String] = []
    var byDisplay: [String: [SpaceInfo]] = [:]
    for space in spaces where space.type == .desktop {
      if byDisplay[space.displayUUID] == nil { order.append(space.displayUUID) }
      byDisplay[space.displayUUID, default: []].append(space)
    }
    return order.map { ($0, byDisplay[$0]!) }
  }
}

/// Plans sending ejected spaces back to their recorded displays once those
/// displays are connected again.
public enum RestorePlanner {

  public struct Plan: Equatable {
    public let preSwitches: [EjectPlanner.PreSwitch]
    public let moves: [EjectPlanner.Move]
    /// Records whose space is already on its recorded display — clear them.
    public let completed: [String]
    /// Records whose space no longer exists — clear them.
    public let stale: [String]
    /// Records whose display is still disconnected — keep them.
    public let waiting: [String]
  }

  public static func plan(spaces: [SpaceInfo], pending: [String: String]) -> Plan {
    let connectedDisplays = Set(spaces.map(\.displayUUID))
    let spaceByUUID = Dictionary(
      spaces.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })

    var restorable: [String: String] = [:]
    var completed: [String] = []
    var stale: [String] = []
    var waiting: [String] = []
    for (spaceUUID, displayUUID) in pending {
      guard let space = spaceByUUID[spaceUUID] else {
        stale.append(spaceUUID)
        continue
      }
      if space.displayUUID == displayUUID {
        completed.append(spaceUUID)
      } else if !connectedDisplays.contains(displayUUID) {
        waiting.append(spaceUUID)
      } else {
        restorable[spaceUUID] = displayUUID
      }
    }

    var preSwitches: [EjectPlanner.PreSwitch] = []
    var moves: [EjectPlanner.Move] = []
    for (displayUUID, desktops) in EjectPlanner.desktopsByDisplay(spaces) {
      let leaving = desktops.enumerated().filter { restorable[$0.element.uuid] != nil }
      guard !leaving.isEmpty else { continue }

      // If the display currently stands on a space that is leaving, switch it
      // to its first staying desktop before the drags.
      if leaving.contains(where: { $0.element.isCurrent }),
        let staying = desktops.enumerated().first(where: {
          restorable[$0.element.uuid] == nil
        })
      {
        preSwitches.append(
          EjectPlanner.PreSwitch(
            displayUUID: displayUUID, toSpaceIndex: staying.offset,
            toSpaceID: staying.element.id))
      }

      moves.append(
        contentsOf: leaving.reversed().map { index, space in
          EjectPlanner.Move(
            spaceID: space.id, spaceUUID: space.uuid,
            sourceDisplayUUID: displayUUID, sourceIndex: index,
            targetDisplayUUID: restorable[space.uuid]!)
        })
    }

    return Plan(
      preSwitches: preSwitches, moves: moves,
      completed: completed.sorted(), stale: stale.sorted(), waiting: waiting.sorted())
  }
}
