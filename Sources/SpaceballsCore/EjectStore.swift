import Foundation

// MARK: - Protocol

public protocol EjectRecordStoring {
  func recordEjection(spaceUUID: String, originalDisplayUUID: String)
  func pendingEjections() -> [String: String]
  func clearEjection(spaceUUID: String)
}

// MARK: - UserDefaults Implementation

/// Persists which display each ejected space came from (space UUID →
/// display UUID), in the same shared suite as SpaceNameStore so the GUI and
/// CLI see one record set: an eject from either process can be restored by
/// the other, and records survive restarts — the eject use case (undock,
/// come back later) naturally spans them.
public final class EjectStore: EjectRecordStoring {
  private static let key = "ejectedSpaces"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = UserDefaults(suiteName: "com.moltenbits.spaceballs.shared")!)
  {
    self.defaults = defaults
  }

  public func recordEjection(spaceUUID: String, originalDisplayUUID: String) {
    var records = pendingEjections()
    records[spaceUUID] = originalDisplayUUID
    defaults.set(records, forKey: Self.key)
  }

  public func pendingEjections() -> [String: String] {
    defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
  }

  public func clearEjection(spaceUUID: String) {
    var records = pendingEjections()
    records.removeValue(forKey: spaceUUID)
    defaults.set(records, forKey: Self.key)
  }
}
