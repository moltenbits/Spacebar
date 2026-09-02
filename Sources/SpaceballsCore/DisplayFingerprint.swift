import Cocoa

/// Stable identity of a physical display, captured at eject time. CGS
/// display UUIDs can be reassigned across reconnects (identical twin
/// monitors, different ports, changed connection order), which strands
/// eject records "awaiting" a UUID that will never return. Restore
/// therefore matches on what the display IS — vendor/model/serial — with
/// the recorded arrangement position breaking ties between identical twins
/// (macOS restores the arrangement itself, so position is stable when the
/// UUID isn't).
public struct DisplayFingerprint: Equatable {
  public let vendorNumber: UInt32
  public let modelNumber: UInt32
  public let serialNumber: UInt32
  public let originX: Double
  public let originY: Double

  public init(
    vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32,
    originX: Double, originY: Double
  ) {
    self.vendorNumber = vendorNumber
    self.modelNumber = modelNumber
    self.serialNumber = serialNumber
    self.originX = originX
    self.originY = originY
  }

  public func sameHardware(as other: DisplayFingerprint) -> Bool {
    vendorNumber == other.vendorNumber && modelNumber == other.modelNumber
      && serialNumber == other.serialNumber
  }

  func originDistance(to other: DisplayFingerprint) -> Double {
    let dx = originX - other.originX
    let dy = originY - other.originY
    return (dx * dx + dy * dy).squareRoot()
  }

  /// The connected display (by UUID) that best matches `recorded`: same
  /// hardware, nearest recorded arrangement position among twins, UUID
  /// order as the deterministic last resort.
  public static func match(
    recorded: DisplayFingerprint, connected: [String: DisplayFingerprint]
  ) -> String? {
    connected
      .filter { $0.value.sameHardware(as: recorded) }
      .min { a, b in
        let da = a.value.originDistance(to: recorded)
        let db = b.value.originDistance(to: recorded)
        return da == db ? a.key < b.key : da < db
      }?.key
  }

  // MARK: - Plist persistence

  public var dictionary: [String: Double] {
    [
      "vendor": Double(vendorNumber), "model": Double(modelNumber),
      "serial": Double(serialNumber), "originX": originX, "originY": originY,
    ]
  }

  public init?(dictionary: [String: Double]) {
    guard let vendor = dictionary["vendor"], let model = dictionary["model"],
      let serial = dictionary["serial"], let x = dictionary["originX"],
      let y = dictionary["originY"]
    else { return nil }
    self.init(
      vendorNumber: UInt32(vendor), modelNumber: UInt32(model),
      serialNumber: UInt32(serial), originX: x, originY: y)
  }
}

extension SpaceManager {
  /// Live fingerprint of a currently connected display.
  static func captureDisplayFingerprint(displayUUID: String) -> DisplayFingerprint? {
    guard let displayID = displayIDForUUID(displayUUID) else { return nil }
    let bounds = CGDisplayBounds(displayID)
    return DisplayFingerprint(
      vendorNumber: CGDisplayVendorNumber(displayID),
      modelNumber: CGDisplayModelNumber(displayID),
      serialNumber: CGDisplaySerialNumber(displayID),
      originX: bounds.origin.x, originY: bounds.origin.y)
  }
}

/// Resolves a recorded display UUID to a currently connected one: the exact
/// UUID when it is present, otherwise the connected display with the same
/// hardware fingerprint (macOS can reassign UUIDs across reconnects). Shared
/// by restore planning and by eject-time origin supersession so both judge
/// "is this display here" the same way.
public struct DisplayResolver {
  public let connectedDisplays: Set<String>
  public let recordedFingerprints: [String: DisplayFingerprint]
  public let connectedFingerprints: [String: DisplayFingerprint]

  public init(
    connectedDisplays: Set<String>,
    recordedFingerprints: [String: DisplayFingerprint],
    connectedFingerprints: [String: DisplayFingerprint]
  ) {
    self.connectedDisplays = connectedDisplays
    self.recordedFingerprints = recordedFingerprints
    self.connectedFingerprints = connectedFingerprints
  }

  public func resolve(_ recorded: String) -> String? {
    if connectedDisplays.contains(recorded) { return recorded }
    guard let fingerprint = recordedFingerprints[recorded],
      let matched = DisplayFingerprint.match(
        recorded: fingerprint, connected: connectedFingerprints),
      connectedDisplays.contains(matched)
    else { return nil }
    return matched
  }
}

extension SpaceManager {
  /// Live fingerprints of every display in `spaces`, keyed by display UUID.
  static func connectedFingerprints(for spaces: [SpaceInfo]) -> [String: DisplayFingerprint] {
    Dictionary(
      uniqueKeysWithValues: Set(spaces.map(\.displayUUID)).compactMap { uuid in
        captureDisplayFingerprint(displayUUID: uuid).map { (uuid, $0) }
      })
  }

  static func displayResolver(
    for spaces: [SpaceInfo], ejectStore: EjectRecordStoring
  ) -> DisplayResolver {
    DisplayResolver(
      connectedDisplays: Set(spaces.map(\.displayUUID)),
      recordedFingerprints: ejectStore.displayFingerprints(),
      connectedFingerprints: connectedFingerprints(for: spaces))
  }
}
