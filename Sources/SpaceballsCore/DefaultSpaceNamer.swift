import Foundation

/// Auto-names each external display's fresh space "Default Space".
///
/// Every display needs a space that is always there: a space can only be
/// moved off a display when another remains, so a pinned anchor space means
/// any named space can always be relocated without first creating a sibling.
/// The built-in display is exempt — it isn't going anywhere, and its spaces
/// stay freely movable.
///
/// A space is pinned by its stored name equaling `SpaceNameStore
/// .defaultSpaceName`; renaming it is the deliberate way to unpin it.
public enum DefaultSpaceNamer {

  /// UUIDs of spaces to auto-name: the sole unnamed desktop space of each
  /// non-built-in display. Displays with several desktop spaces, or whose
  /// sole space already carries a name, are left alone — re-running the
  /// assignment is idempotent.
  public static func assignableSpaceUUIDs(
    spaces: [SpaceInfo],
    builtinDisplayUUID: String?,
    existingNames: [String: String]
  ) -> [String] {
    let desktops = spaces.filter { $0.type == .desktop }
    var displayOrder: [String] = []
    var byDisplay: [String: [SpaceInfo]] = [:]
    for space in desktops {
      if byDisplay[space.displayUUID] == nil { displayOrder.append(space.displayUUID) }
      byDisplay[space.displayUUID, default: []].append(space)
    }

    var assignable: [String] = []
    for displayUUID in displayOrder where displayUUID != builtinDisplayUUID {
      guard let displaySpaces = byDisplay[displayUUID], displaySpaces.count == 1,
        let sole = displaySpaces.first, existingNames[sole.uuid] == nil
      else { continue }
      assignable.append(sole.uuid)
    }
    return assignable
  }

  /// Applies the assignment through `store`.
  public static func assignNames(
    spaces: [SpaceInfo],
    builtinDisplayUUID: String?,
    store: SpaceNameStoring
  ) {
    for uuid in assignableSpaceUUIDs(
      spaces: spaces, builtinDisplayUUID: builtinDisplayUUID,
      existingNames: store.allCustomNames())
    {
      store.setCustomName(SpaceNameStore.defaultSpaceName, forSpaceUUID: uuid)
    }
  }
}
