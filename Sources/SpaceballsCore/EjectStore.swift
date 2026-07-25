import Foundation

// MARK: - Protocol

public protocol EjectRecordStoring {
  func recordEjection(spaceUUID: String, originalDisplayUUID: String)
  func pendingEjections() -> [String: String]
  func clearEjection(spaceUUID: String)
  /// Records whose display has been observed ABSENT since the eject —
  /// auto-restore only fires for these, so spontaneous display events can't
  /// undo an eject whose displays never went away.
  func armedEjections() -> Set<String>
  func armEjections(spaceUUIDs: [String])
}

// MARK: - UserDefaults Implementation

/// Persists which display each ejected space came from (space UUID →
/// display UUID), in the same shared suite as SpaceNameStore so the GUI and
/// CLI see one record set: an eject from either process can be restored by
/// the other, and records survive restarts — the eject use case (undock,
/// come back later) naturally spans them.
public final class EjectStore: EjectRecordStoring {
  private static let key = "ejectedSpaces"
  private static let armedKey = "armedEjectedSpaces"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = UserDefaults(suiteName: "com.moltenbits.spaceballs.shared")!)
  {
    self.defaults = defaults
  }

  public func recordEjection(spaceUUID: String, originalDisplayUUID: String) {
    var records = pendingEjections()
    records[spaceUUID] = originalDisplayUUID
    defaults.set(records, forKey: Self.key)
    // A fresh eject starts disarmed — its display is present right now and
    // must be observed absent before auto-restore may touch the record.
    disarm(spaceUUID: spaceUUID)
  }

  public func pendingEjections() -> [String: String] {
    defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
  }

  public func clearEjection(spaceUUID: String) {
    var records = pendingEjections()
    records.removeValue(forKey: spaceUUID)
    defaults.set(records, forKey: Self.key)
    disarm(spaceUUID: spaceUUID)
  }

  public func armedEjections() -> Set<String> {
    Set(defaults.stringArray(forKey: Self.armedKey) ?? [])
  }

  public func armEjections(spaceUUIDs: [String]) {
    guard !spaceUUIDs.isEmpty else { return }
    defaults.set(
      Array(armedEjections().union(spaceUUIDs)).sorted(), forKey: Self.armedKey)
  }

  private func disarm(spaceUUID: String) {
    let armed = armedEjections()
    guard armed.contains(spaceUUID) else { return }
    defaults.set(Array(armed.subtracting([spaceUUID])).sorted(), forKey: Self.armedKey)
  }
}
