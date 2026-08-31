import Cocoa

// MARK: - Data Models

/// A window's frame stored as offsets relative to the captured display's
/// `visibleFrame` origin in AX coordinates (top-left origin).
public struct WindowFrame: Codable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

/// All app frames for one logical Space on one display. `spaceUUID` records
/// the macOS Space that most recently captured or migrated the layout; named
/// Spaces are keyed durably by name rather than by that transient UUID.
public struct SpaceDisplayLayout: Codable {
  public var spaceUUID: String
  public var displayUUID: String
  public var apps: [String: WindowFrame]
  public var capturedAt: Date
  /// Per-app timestamps let migrations merge layouts without an older frame
  /// for one app overwriting a newer frame for another. Legacy records omit
  /// this field and fall back to `capturedAt` for every app.
  public var appCapturedAt: [String: Date]?

  public init(
    spaceUUID: String, displayUUID: String,
    apps: [String: WindowFrame] = [:], capturedAt: Date = Date(),
    appCapturedAt: [String: Date]? = nil
  ) {
    self.spaceUUID = spaceUUID
    self.displayUUID = displayUUID
    self.apps = apps
    self.capturedAt = capturedAt
    self.appCapturedAt = appCapturedAt
  }
}

/// Legacy workspace-keyed layout decoded only as migration input. New captures
/// use `SpaceDisplayLayout` for both workspace and ordinary restore paths.
struct LegacyWorkspaceDisplayLayout: Codable {
  var workspaceID: String
  var displayUUID: String
  var apps: [String: WindowFrame]
  var capturedAt: Date
  var appCapturedAt: [String: Date]?

  init(
    workspaceID: String, displayUUID: String,
    apps: [String: WindowFrame] = [:], capturedAt: Date = Date(),
    appCapturedAt: [String: Date]? = nil
  ) {
    self.workspaceID = workspaceID
    self.displayUUID = displayUUID
    self.apps = apps
    self.capturedAt = capturedAt
    self.appCapturedAt = appCapturedAt
  }
}

/// Result of one attempt to apply a logical Space layout. Bundle IDs remain
/// pending until at least one eligible window for that app is resized.
public struct WindowLayoutRestoreAttempt: Equatable {
  public let hasLayout: Bool
  public let movedWindows: Int
  public let restoredBundleIDs: Set<String>
  public let pendingBundleIDs: Set<String>

  public init(
    hasLayout: Bool,
    movedWindows: Int,
    restoredBundleIDs: Set<String>,
    pendingBundleIDs: Set<String>
  ) {
    self.hasLayout = hasLayout
    self.movedWindows = movedWindows
    self.restoredBundleIDs = restoredBundleIDs
    self.pendingBundleIDs = pendingBundleIDs
  }
}

// MARK: - Display Helpers

/// EDID-derived UUID for a screen — stable across plug/unplug for the same physical monitor.
public func spaceballsDisplayUUID(for screen: NSScreen) -> String? {
  guard
    let screenNumber = screen.deviceDescription[
      NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
    let cfUUID = CGDisplayCreateUUIDFromDisplayID(screenNumber)?.takeUnretainedValue()
  else { return nil }
  return CFUUIDCreateString(nil, cfUUID) as String
}

/// Finds the NSScreen whose EDID UUID matches the given displayUUID.
public func spaceballsScreen(forDisplayUUID uuid: String) -> NSScreen? {
  NSScreen.screens.first { spaceballsDisplayUUID(for: $0) == uuid }
}

/// AX origin of a screen (top-left origin from primary display top).
/// AX X = Cocoa X. AX Y = primaryDisplayHeight - (Cocoa Y + height).
public func spaceballsAXOrigin(of screen: NSScreen) -> CGPoint {
  let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
  let visible = screen.visibleFrame
  return CGPoint(x: visible.minX, y: primaryHeight - visible.maxY)
}

// MARK: - Window Layout Store

public final class WindowLayoutStore {
  private let defaults: UserDefaults
  private let spaceManager: SpaceManager
  private let spaceNameStore: SpaceNameStoring
  private let layoutsKey = "windowLayouts"
  private let lastDisplayKey = "spaceLastDisplay"
  private let identityAssociationsKey = "spaceLayoutIdentities"
  private let workspaceLayoutsKey = "workspaceWindowLayouts"
  private let workspaceAssociationsKey = "workspaceSpaceAssociations"

  private var layouts: [String: SpaceDisplayLayout]
  private var lastSeenDisplay: [String: String]
  /// Read-only migration source. New captures never write this legacy store.
  private var legacyWorkspaceLayouts: [String: LegacyWorkspaceDisplayLayout]
  private var legacyWorkspaceBySpaceUUID: [String: String]
  private var identityBySpaceUUID: [String: String]
  private var spaceNameObserver: NSObjectProtocol?

  public init(
    defaults: UserDefaults = .standard,
    spaceManager: SpaceManager,
    spaceNameStore: SpaceNameStoring
  ) {
    self.defaults = defaults
    self.spaceManager = spaceManager
    self.spaceNameStore = spaceNameStore

    if let data = defaults.data(forKey: layoutsKey),
      let decoded = try? JSONDecoder().decode([String: SpaceDisplayLayout].self, from: data)
    {
      self.layouts = decoded
    } else {
      self.layouts = [:]
    }

    self.lastSeenDisplay = (defaults.dictionary(forKey: lastDisplayKey) as? [String: String]) ?? [:]

    if let data = defaults.data(forKey: workspaceLayoutsKey),
      let decoded = try? JSONDecoder().decode(
        [String: LegacyWorkspaceDisplayLayout].self, from: data)
    {
      self.legacyWorkspaceLayouts = decoded
    } else {
      self.legacyWorkspaceLayouts = [:]
    }

    self.legacyWorkspaceBySpaceUUID =
      (defaults.dictionary(forKey: workspaceAssociationsKey) as? [String: String]) ?? [:]
    self.identityBySpaceUUID =
      (defaults.dictionary(forKey: identityAssociationsKey) as? [String: String]) ?? [:]

    self.spaceNameObserver = NotificationCenter.default.addObserver(
      forName: SpaceNameStore.customNameDidChangeNotification,
      object: spaceNameStore,
      queue: nil
    ) { [weak self] notification in
      guard
        let spaceUUID = notification.userInfo?[SpaceNameStore.spaceUUIDUserInfoKey] as? String
      else { return }
      _ = self?.resolveIdentity(spaceUUID: spaceUUID)
    }
  }

  deinit {
    if let spaceNameObserver {
      NotificationCenter.default.removeObserver(spaceNameObserver)
    }
  }

  // MARK: - Persistence

  public func layout(spaceUUID: String, displayUUID: String) -> SpaceDisplayLayout? {
    let identity = resolveIdentity(spaceUUID: spaceUUID)
    return layouts[Self.key(identity, displayUUID)]
  }

  /// Prepares the one logical layout used by every restore caller. The optional
  /// workspace ID exists only to migrate the pre-unification workspace store;
  /// it never becomes a live layout identity.
  @discardableResult
  public func prepareSpace(
    spaceUUID: String,
    displayUUID: String,
    legacyWorkspaceID: String? = nil,
    bundleIDs: Set<String> = []
  ) -> Bool {
    let identity = resolveIdentity(spaceUUID: spaceUUID)
    if let legacyWorkspaceID {
      migrateLegacyWorkspace(
        id: legacyWorkspaceID,
        to: identity,
        currentSpaceUUID: spaceUUID)
      migrateAssociatedLegacyLayouts(
        workspaceID: legacyWorkspaceID,
        to: identity,
        currentSpaceUUID: spaceUUID)

      migrateNewestLegacyFrames(
        to: identity,
        currentSpaceUUID: spaceUUID,
        displayUUID: displayUUID,
        bundleIDs: bundleIDs)
    }
    return layouts[Self.key(identity, displayUUID)] != nil
  }

  public func setFrame(
    bundleID: String, frame: WindowFrame, spaceUUID: String, displayUUID: String
  ) {
    let identity = resolveIdentity(spaceUUID: spaceUUID)
    let key = Self.key(identity, displayUUID)
    var layout =
      layouts[key]
      ?? SpaceDisplayLayout(spaceUUID: spaceUUID, displayUUID: displayUUID)
    let capturedAt = Date()
    layout.spaceUUID = spaceUUID
    layout.apps[bundleID] = frame
    layout.capturedAt = capturedAt
    layout.appCapturedAt = (layout.appCapturedAt ?? [:]).merging(
      [bundleID: capturedAt], uniquingKeysWith: { _, newest in newest })
    layouts[key] = layout
    persistLayouts()
  }

  public func clearAll() {
    layouts = [:]
    lastSeenDisplay = [:]
    legacyWorkspaceLayouts = [:]
    legacyWorkspaceBySpaceUUID = [:]
    identityBySpaceUUID = [:]
    defaults.removeObject(forKey: layoutsKey)
    defaults.removeObject(forKey: lastDisplayKey)
    defaults.removeObject(forKey: identityAssociationsKey)
    defaults.removeObject(forKey: workspaceLayoutsKey)
    defaults.removeObject(forKey: workspaceAssociationsKey)
  }

  public func lastSeenDisplayUUID(forSpace spaceUUID: String) -> String? {
    lastSeenDisplay[spaceUUID]
  }

  public func setLastSeenDisplay(spaceUUID: String, displayUUID: String) {
    lastSeenDisplay[spaceUUID] = displayUUID
    defaults.set(lastSeenDisplay, forKey: lastDisplayKey)
  }

  // MARK: - Capture

  /// Captures the focused window's frame for an app and stores it against the
  /// logical Space and display the window currently sits on.
  public func captureWindow(pid: pid_t, bundleID: String) {
    let axApp = AXUIElementCreateApplication(pid)
    var ref: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success,
      let windowRef = ref
    else { return }
    // swiftlint:disable:next force_cast
    let element = windowRef as! AXUIElement
    captureWindow(element: element, bundleID: bundleID)
  }

  /// Captures a specific AX window element. Resolves its display + the current
  /// Space on that display, converts to display-relative coords, and persists.
  public func captureWindow(element: AXUIElement, bundleID: String) {
    guard let position = SpaceManager.axPosition(element),
      let size = SpaceManager.axSize(element)
    else { return }
    guard let screen = WindowResizer.screen(for: element),
      let displayUUID = spaceballsDisplayUUID(for: screen)
    else { return }

    let spaces = spaceManager.getAllSpaces()
    guard let currentSpace = spaces.first(where: { $0.isCurrent && $0.displayUUID == displayUUID })
    else { return }

    let origin = spaceballsAXOrigin(of: screen)
    let relative = WindowFrame(
      x: Double(position.x - origin.x),
      y: Double(position.y - origin.y),
      width: Double(size.width),
      height: Double(size.height)
    )
    setFrame(
      bundleID: bundleID, frame: relative,
      spaceUUID: currentSpace.uuid, displayUUID: displayUUID)
    setLastSeenDisplay(spaceUUID: currentSpace.uuid, displayUUID: displayUUID)
  }

  // MARK: - Restore

  /// Applies the logical Space's saved layout for the destination display to
  /// each saved app's windows **that are actually on the current Space UUID**.
  /// Workspace polling and ordinary display-change restoration both call this
  /// method; `requestedBundleIDs` only narrows a retry attempt.
  ///
  /// The per-window space check exists because `kAXWindowsAttribute` returns windows
  /// from every space, not just the current one (despite Apple's documentation implying
  /// otherwise — Safari, iTerm, and JetBrains IDEs all demonstrate this). Without the
  /// check, restoring a space that moved displays stamped cross-display coordinates
  /// onto other spaces' windows, physically dragging them into whatever space was
  /// active on the target display (issue #3).
  public func restore(
    spaceUUID: String,
    displayUUID: String,
    requestedBundleIDs: Set<String>? = nil
  ) -> WindowLayoutRestoreAttempt {
    let token = Diagnostics.beginTiming(
      "layout-restore", "restore",
      extras: ["space": spaceUUID, "display": displayUUID])
    guard let layout = layout(spaceUUID: spaceUUID, displayUUID: displayUUID) else {
      Diagnostics.endTiming(token, outcome: "no-layout-for-pair")
      return WindowLayoutRestoreAttempt(
        hasLayout: false,
        movedWindows: 0,
        restoredBundleIDs: [],
        pendingBundleIDs: [])
    }
    let result = apply(
      apps: layout.apps,
      targetSpaceUUID: spaceUUID,
      displayUUID: displayUUID,
      requestedBundleIDs: requestedBundleIDs)
    Diagnostics.endTiming(
      token,
      outcome:
        "moved=\(result.movedWindows) restored=\(result.restoredBundleIDs.count) pending=\(result.pendingBundleIDs.count)"
    )
    return result
  }

  // MARK: - Space Filtering

  /// Resolves a space UUID to its ManagedSpaceID via the current CGS snapshot.
  func spaceID(forUUID uuid: String) -> UInt64? {
    spaceManager.getAllSpaces().first { $0.uuid == uuid }?.id
  }

  /// True when the window belongs to the given space. Windows CGS has no space record
  /// for return false — skipping a restore is recoverable, moving a window across
  /// spaces is not. Sticky windows report every space they appear on, so they pass
  /// for any of them.
  func windowIsOnSpace(windowID: Int, spaceID: UInt64) -> Bool {
    spaceManager.spaceIDs(forWindowID: windowID).contains(spaceID)
  }

  // MARK: - Internals

  private func persistLayouts() {
    if let data = try? JSONEncoder().encode(layouts) {
      defaults.set(data, forKey: layoutsKey)
    }
  }

  private func persistIdentityAssociations() {
    defaults.set(identityBySpaceUUID, forKey: identityAssociationsKey)
  }

  /// Resolves a transient macOS UUID to the one persistence identity used by
  /// capture and restore. Unique custom names survive Space recreation;
  /// unnamed and ambiguously named Spaces stay UUID-isolated.
  private func resolveIdentity(spaceUUID: String) -> String {
    let uuidIdentity = Self.uuidIdentity(spaceUUID)
    migrateLegacyUUIDLayouts(spaceUUID: spaceUUID, to: uuidIdentity)

    let names = spaceNameStore.allCustomNames()
    guard let rawName = names[spaceUUID] else {
      if let previous = identityBySpaceUUID[spaceUUID] {
        if previous != uuidIdentity {
          migrateLayouts(
            from: previous,
            to: uuidIdentity,
            currentSpaceUUID: spaceUUID)
        }
        identityBySpaceUUID.removeValue(forKey: spaceUUID)
        persistIdentityAssociations()
      }
      return uuidIdentity
    }

    let normalizedName = Self.normalizedName(rawName)
    let currentUUIDs = Set(spaceManager.getAllSpaces().map(\.uuid))
    let matchingUUIDs = names.compactMap { uuid, candidate -> String? in
      guard currentUUIDs.contains(uuid), Self.normalizedName(candidate) == normalizedName
      else { return nil }
      return uuid
    }

    guard matchingUUIDs.count == 1 else {
      Diagnostics.log(
        "layout-restore",
        "name identity ambiguous — using Space UUID name=\(rawName) matches=\(matchingUUIDs.count)"
      )
      return uuidIdentity
    }

    let namedIdentity = Self.namedIdentity(normalizedName)
    if let previous = identityBySpaceUUID[spaceUUID], previous != namedIdentity {
      migrateLayouts(
        from: previous,
        to: namedIdentity,
        currentSpaceUUID: spaceUUID)
    }
    migrateLayouts(
      from: uuidIdentity,
      to: namedIdentity,
      currentSpaceUUID: spaceUUID)
    if identityBySpaceUUID[spaceUUID] != namedIdentity {
      identityBySpaceUUID[spaceUUID] = namedIdentity
      persistIdentityAssociations()
    }
    return namedIdentity
  }

  /// Moves raw pre-unification `UUID|display` records into the UUID fallback
  /// namespace. A later unique-name resolution promotes them again.
  private func migrateLegacyUUIDLayouts(
    spaceUUID: String,
    to identity: String,
    currentSpaceUUID: String? = nil
  ) {
    let prefix = "\(spaceUUID)|"
    let sourceKeys = layouts.keys.filter { $0.hasPrefix(prefix) }
    guard !sourceKeys.isEmpty else { return }
    let destinationSpaceUUID = currentSpaceUUID ?? spaceUUID

    var changed = false
    for sourceKey in sourceKeys {
      guard let source = layouts[sourceKey] else { continue }
      changed =
        merge(
          source,
          into: identity,
          currentSpaceUUID: destinationSpaceUUID) || changed
      layouts.removeValue(forKey: sourceKey)
      changed = true
    }
    if changed { persistLayouts() }
  }

  /// Uses the old persisted workspace-to-Space association as a precise bridge
  /// for raw UUID records, including apps that are no longer launcher entries.
  private func migrateAssociatedLegacyLayouts(
    workspaceID: String,
    to identity: String,
    currentSpaceUUID: String
  ) {
    let associatedUUIDs = legacyWorkspaceBySpaceUUID.compactMap { uuid, associatedID in
      associatedID == workspaceID ? uuid : nil
    }
    for associatedUUID in associatedUUIDs {
      migrateLegacyUUIDLayouts(
        spaceUUID: associatedUUID,
        to: identity,
        currentSpaceUUID: currentSpaceUUID)
    }
  }

  /// Migrates all display layouts when a Space is renamed or moves from its
  /// UUID fallback into a durable unique-name identity.
  private func migrateLayouts(
    from sourceIdentity: String,
    to targetIdentity: String,
    currentSpaceUUID: String
  ) {
    guard sourceIdentity != targetIdentity else { return }
    let prefix = "\(sourceIdentity)|"
    let sourceKeys = layouts.keys.filter { $0.hasPrefix(prefix) }
    guard !sourceKeys.isEmpty else { return }

    var changed = false
    for sourceKey in sourceKeys {
      guard let source = layouts[sourceKey] else { continue }
      changed =
        merge(
          source,
          into: targetIdentity,
          currentSpaceUUID: currentSpaceUUID) || changed
      layouts.removeValue(forKey: sourceKey)
      changed = true
    }
    if changed { persistLayouts() }
  }

  /// Promotes the old workspace-ID namespace into the logical named-Space
  /// namespace. Legacy records remain as read-only migration input so the
  /// operation is safe and idempotent across upgrades and rollbacks.
  private func migrateLegacyWorkspace(
    id workspaceID: String,
    to identity: String,
    currentSpaceUUID: String
  ) {
    var changed = false
    var migratedBundleIDs: Set<String> = []
    for legacy in legacyWorkspaceLayouts.values where legacy.workspaceID == workspaceID {
      guard !legacy.apps.isEmpty else { continue }
      let source = SpaceDisplayLayout(
        spaceUUID: currentSpaceUUID,
        displayUUID: legacy.displayUUID,
        apps: legacy.apps,
        capturedAt: legacy.capturedAt,
        appCapturedAt: legacy.appCapturedAt)
      changed =
        merge(
          source,
          into: identity,
          currentSpaceUUID: currentSpaceUUID) || changed
      migratedBundleIDs.formUnion(legacy.apps.keys)
    }
    if changed {
      persistLayouts()
      Diagnostics.log(
        "layout-restore",
        "migrated legacy workspace layout apps=\(migratedBundleIDs.count)")
    }
  }

  /// Best-effort bridge for workspace layouts captured before stable workspace
  /// records existed. It considers only raw legacy UUID records, never another
  /// logical named Space, and chooses the newest frame independently per app.
  private func migrateNewestLegacyFrames(
    to identity: String,
    currentSpaceUUID: String,
    displayUUID: String,
    bundleIDs: Set<String>
  ) {
    guard !bundleIDs.isEmpty else { return }
    let targetKey = Self.key(identity, displayUUID)
    let existingBundleIDs = Set(layouts[targetKey]?.apps.keys.map { $0 } ?? [])
    let rawLegacyLayouts = layouts.filter { key, layout in
      !key.hasPrefix("name:") && !key.hasPrefix("uuid:")
        && layout.displayUUID == displayUUID
    }.values

    var apps: [String: WindowFrame] = [:]
    var timestamps: [String: Date] = [:]
    for bundleID in bundleIDs where !existingBundleIDs.contains(bundleID) {
      for layout in rawLegacyLayouts {
        guard let frame = layout.apps[bundleID] else { continue }
        let timestamp = layout.appCapturedAt?[bundleID] ?? layout.capturedAt
        if timestamp > (timestamps[bundleID] ?? .distantPast) {
          apps[bundleID] = frame
          timestamps[bundleID] = timestamp
        }
      }
    }
    guard !apps.isEmpty else { return }

    let source = SpaceDisplayLayout(
      spaceUUID: currentSpaceUUID,
      displayUUID: displayUUID,
      apps: apps,
      capturedAt: timestamps.values.max() ?? .distantPast,
      appCapturedAt: timestamps)
    if merge(source, into: identity, currentSpaceUUID: currentSpaceUUID) {
      persistLayouts()
      Diagnostics.log(
        "layout-restore",
        "seeded logical Space layout apps=\(apps.count)")
    }
  }

  /// Newest-frame-wins merge, independently per bundle ID.
  @discardableResult
  private func merge(
    _ source: SpaceDisplayLayout,
    into identity: String,
    currentSpaceUUID: String
  ) -> Bool {
    let targetKey = Self.key(identity, source.displayUUID)
    var target =
      layouts[targetKey]
      ?? SpaceDisplayLayout(
        spaceUUID: currentSpaceUUID,
        displayUUID: source.displayUUID,
        capturedAt: .distantPast,
        appCapturedAt: [:])
    var targetTimestamps =
      target.appCapturedAt
      ?? Dictionary(
        uniqueKeysWithValues: target.apps.keys.map { ($0, target.capturedAt) })
    var changed = target.spaceUUID != currentSpaceUUID
    target.spaceUUID = currentSpaceUUID

    for (bundleID, frame) in source.apps {
      let sourceTimestamp = source.appCapturedAt?[bundleID] ?? source.capturedAt
      let targetTimestamp = targetTimestamps[bundleID] ?? .distantPast
      if target.apps[bundleID] == nil || sourceTimestamp > targetTimestamp {
        target.apps[bundleID] = frame
        targetTimestamps[bundleID] = sourceTimestamp
        changed = true
      }
    }

    let newestTimestamp = targetTimestamps.values.max() ?? target.capturedAt
    if newestTimestamp != target.capturedAt {
      target.capturedAt = newestTimestamp
      changed = true
    }
    target.appCapturedAt = targetTimestamps
    if changed { layouts[targetKey] = target }
    return changed
  }

  private static func normalizedName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }

  private static func namedIdentity(_ normalizedName: String) -> String {
    "name:\(Data(normalizedName.utf8).base64EncodedString())"
  }

  private static func uuidIdentity(_ uuid: String) -> String {
    "uuid:\(uuid.lowercased())"
  }

  private func apply(
    apps: [String: WindowFrame],
    targetSpaceUUID: String,
    displayUUID: String,
    requestedBundleIDs: Set<String>?
  ) -> WindowLayoutRestoreAttempt {
    let availableBundleIDs = Set(apps.keys)
    let candidateBundleIDs =
      requestedBundleIDs.map { $0.intersection(availableBundleIDs) } ?? availableBundleIDs
    var pendingBundleIDs = candidateBundleIDs

    guard let screen = spaceballsScreen(forDisplayUUID: displayUUID) else {
      Diagnostics.log("layout-restore", "display not attached")
      return WindowLayoutRestoreAttempt(
        hasLayout: true, movedWindows: 0,
        restoredBundleIDs: [], pendingBundleIDs: pendingBundleIDs)
    }
    guard let targetSpaceID = spaceID(forUUID: targetSpaceUUID) else {
      Diagnostics.log("layout-restore", "target Space UUID unresolved")
      return WindowLayoutRestoreAttempt(
        hasLayout: true, movedWindows: 0,
        restoredBundleIDs: [], pendingBundleIDs: pendingBundleIDs)
    }

    let origin = spaceballsAXOrigin(of: screen)
    var movedWindows = 0
    var restoredBundleIDs: Set<String> = []

    Diagnostics.log(
      "layout-restore",
      "applying layout apps=\(candidateBundleIDs.count) targetSpaceID=\(targetSpaceID)")

    for bundleID in candidateBundleIDs {
      guard let relative = apps[bundleID] else { continue }
      let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      if runningApps.isEmpty {
        Diagnostics.log("layout-restore", "waiting — app not running", app: bundleID)
        continue
      }

      let absolute = CGRect(
        x: origin.x + CGFloat(relative.x),
        y: origin.y + CGFloat(relative.y),
        width: CGFloat(relative.width),
        height: CGFloat(relative.height))

      for app in runningApps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard
          AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
          let windows = ref as? [AXUIElement]
        else {
          Diagnostics.log("layout-restore", "waiting — windows unreadable", app: bundleID)
          continue
        }

        for window in windows {
          var windowID: CGWindowID = 0
          guard _AXUIElementGetWindow(window, &windowID) == .success else {
            Diagnostics.log(
              "layout-restore", "skip window — CGWindowID unresolved", app: bundleID)
            continue
          }
          guard windowIsOnSpace(windowID: Int(windowID), spaceID: targetSpaceID) else {
            Diagnostics.log(
              "layout-restore",
              "skip window=\(windowID) — not on target space \(targetSpaceID)", app: bundleID)
            continue
          }
          guard
            (try? WindowResizer.setFrame(window, frame: absolute, label: "restore")) != nil
          else { continue }
          movedWindows += 1
          restoredBundleIDs.insert(bundleID)
          pendingBundleIDs.remove(bundleID)
        }
      }
    }

    return WindowLayoutRestoreAttempt(
      hasLayout: true,
      movedWindows: movedWindows,
      restoredBundleIDs: restoredBundleIDs,
      pendingBundleIDs: pendingBundleIDs)
  }

  private static func key(_ identity: String, _ displayUUID: String) -> String {
    "\(identity)|\(displayUUID)"
  }
}
