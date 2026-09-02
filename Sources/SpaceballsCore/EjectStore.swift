import Foundation

// MARK: - Protocol

public protocol EjectRecordStoring {
  /// Adds `originalDisplayUUID` to the space's origins (most recent last). A
  /// space keeps one origin per site it has been ejected from, so an eject
  /// at home never erases where the space lives at the office.
  func recordEjection(spaceUUID: String, originalDisplayUUID: String)
  /// Space UUID → the displays it was ejected from, oldest first.
  func pendingEjections() -> [String: [String]]
  /// Drops one origin; the space's record goes with its last origin.
  func clearEjection(spaceUUID: String, displayUUID: String)
  /// Drops several origins at once (superseded by a fresh eject).
  func removeOrigins(spaceUUID: String, displayUUIDs: [String])
  /// Displays observed ABSENT since their records were made — auto-restore
  /// only fires for origins on these, so spontaneous display events can't
  /// undo an eject whose displays never went away.
  func armedDisplays() -> Set<String>
  func armDisplays(_ displayUUIDs: [String])
  /// Which space was active on each display at eject time (display UUID →
  /// space UUID), captured before the pre-switch onto the Default Space so
  /// restore can reactivate it.
  func recordActiveSpace(displayUUID: String, spaceUUID: String)
  func activeSpaceRecords() -> [String: String]
  func clearActiveSpace(displayUUID: String)
  /// Hardware identity of each recorded home display, so restore can find
  /// the display again when macOS reassigns its UUID across a reconnect.
  func recordDisplayFingerprint(displayUUID: String, fingerprint: DisplayFingerprint)
  func displayFingerprints() -> [String: DisplayFingerprint]
}

// MARK: - UserDefaults Implementation

/// Persists which displays each ejected space came from (space UUID →
/// display UUIDs), in the same shared suite as SpaceNameStore so the GUI and
/// CLI see one record set: an eject from either process can be restored by
/// the other, and records survive restarts — the eject use case (undock,
/// come back later) naturally spans them.
///
/// Records written before multi-origin support hold a single display UUID
/// per space; they are read as one-element origin lists and rewritten in the
/// current shape on the next change.
public final class EjectStore: EjectRecordStoring {
  private static let key = "ejectedSpaces"
  private static let armedDisplaysKey = "armedEjectDisplays"
  private static let legacyArmedSpacesKey = "armedEjectedSpaces"
  private static let activeSpacesKey = "ejectedActiveSpaces"
  private static let fingerprintsKey = "ejectedDisplayFingerprints"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults = UserDefaults(suiteName: "com.moltenbits.spaceballs.shared")!)
  {
    self.defaults = defaults
  }

  public func recordEjection(spaceUUID: String, originalDisplayUUID: String) {
    var records = pendingEjections()
    var origins = records[spaceUUID] ?? []
    origins.removeAll { $0 == originalDisplayUUID }
    origins.append(originalDisplayUUID)
    records[spaceUUID] = origins
    save(records)
    // A fresh eject from this display means it is present right now — it
    // must be observed absent before auto-restore may touch its records.
    disarm(displayUUID: originalDisplayUUID)
  }

  public func pendingEjections() -> [String: [String]] {
    guard let raw = defaults.dictionary(forKey: Self.key) else { return [:] }
    var records: [String: [String]] = [:]
    for (spaceUUID, value) in raw {
      if let origins = value as? [String] {
        if !origins.isEmpty { records[spaceUUID] = origins }
      } else if let origin = value as? String {
        records[spaceUUID] = [origin]
      }
    }
    return records
  }

  public func clearEjection(spaceUUID: String, displayUUID: String) {
    removeOrigins(spaceUUID: spaceUUID, displayUUIDs: [displayUUID])
  }

  public func removeOrigins(spaceUUID: String, displayUUIDs: [String]) {
    var records = pendingEjections()
    guard var origins = records[spaceUUID] else { return }
    origins.removeAll { displayUUIDs.contains($0) }
    records[spaceUUID] = origins.isEmpty ? nil : origins
    save(records)
    pruneUnreferenced(records)
  }

  private func save(_ records: [String: [String]]) {
    defaults.set(records, forKey: Self.key)
  }

  public func armedDisplays() -> Set<String> {
    migrateLegacyArmedSpaces()
    return Set(defaults.stringArray(forKey: Self.armedDisplaysKey) ?? [])
  }

  public func armDisplays(_ displayUUIDs: [String]) {
    guard !displayUUIDs.isEmpty else { return }
    defaults.set(
      Array(armedDisplays().union(displayUUIDs)).sorted(), forKey: Self.armedDisplaysKey)
  }

  private func disarm(displayUUID: String) {
    let armed = armedDisplays()
    guard armed.contains(displayUUID) else { return }
    defaults.set(Array(armed.subtracting([displayUUID])).sorted(), forKey: Self.armedDisplaysKey)
  }

  /// Arming used to be tracked per SPACE; each legacy entry maps onto that
  /// space's (single) origin display.
  private func migrateLegacyArmedSpaces() {
    guard let legacy = defaults.stringArray(forKey: Self.legacyArmedSpacesKey) else { return }
    let records = pendingEjections()
    let displays = Set(legacy.flatMap { records[$0] ?? [] })
    let current = Set(defaults.stringArray(forKey: Self.armedDisplaysKey) ?? [])
    defaults.set(Array(current.union(displays)).sorted(), forKey: Self.armedDisplaysKey)
    defaults.removeObject(forKey: Self.legacyArmedSpacesKey)
  }

  public func recordActiveSpace(displayUUID: String, spaceUUID: String) {
    var records = activeSpaceRecords()
    records[displayUUID] = spaceUUID
    defaults.set(records, forKey: Self.activeSpacesKey)
  }

  public func activeSpaceRecords() -> [String: String] {
    defaults.dictionary(forKey: Self.activeSpacesKey) as? [String: String] ?? [:]
  }

  public func clearActiveSpace(displayUUID: String) {
    var records = activeSpaceRecords()
    records.removeValue(forKey: displayUUID)
    defaults.set(records, forKey: Self.activeSpacesKey)
  }

  public func recordDisplayFingerprint(displayUUID: String, fingerprint: DisplayFingerprint) {
    var records = rawFingerprints()
    records[displayUUID] = fingerprint.dictionary
    defaults.set(records, forKey: Self.fingerprintsKey)
  }

  public func displayFingerprints() -> [String: DisplayFingerprint] {
    rawFingerprints().compactMapValues(DisplayFingerprint.init(dictionary:))
  }

  private func rawFingerprints() -> [String: [String: Double]] {
    defaults.dictionary(forKey: Self.fingerprintsKey) as? [String: [String: Double]] ?? [:]
  }

  /// Drops fingerprints and arming for displays no origin references anymore.
  private func pruneUnreferenced(_ records: [String: [String]]) {
    let referenced = Set(records.values.flatMap { $0 })
    let fingerprints = rawFingerprints().filter { referenced.contains($0.key) }
    defaults.set(fingerprints, forKey: Self.fingerprintsKey)
    let armed = armedDisplays().filter { referenced.contains($0) }
    defaults.set(Array(armed).sorted(), forKey: Self.armedDisplaysKey)
  }
}
