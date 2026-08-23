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

/// All apps' frames for a specific (Space, display) pairing.
public struct SpaceDisplayLayout: Codable {
  public var spaceUUID: String
  public var displayUUID: String
  public var apps: [String: WindowFrame]
  public var capturedAt: Date

  public init(
    spaceUUID: String, displayUUID: String,
    apps: [String: WindowFrame] = [:], capturedAt: Date = Date()
  ) {
    self.spaceUUID = spaceUUID
    self.displayUUID = displayUUID
    self.apps = apps
    self.capturedAt = capturedAt
  }
}

/// Saved app frames for a persisted workspace on a specific display. Unlike
/// `SpaceDisplayLayout`, this survives deletion and recreation of the backing
/// macOS Space because `workspaceID` comes from `WorkspaceConfig.id`.
public struct WorkspaceDisplayLayout: Codable {
  public var workspaceID: String
  public var displayUUID: String
  public var apps: [String: WindowFrame]
  public var capturedAt: Date

  public init(
    workspaceID: String, displayUUID: String,
    apps: [String: WindowFrame] = [:], capturedAt: Date = Date()
  ) {
    self.workspaceID = workspaceID
    self.displayUUID = displayUUID
    self.apps = apps
    self.capturedAt = capturedAt
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
  private let layoutsKey = "windowLayouts"
  private let lastDisplayKey = "spaceLastDisplay"
  private let workspaceLayoutsKey = "workspaceWindowLayouts"
  private let workspaceAssociationsKey = "workspaceSpaceAssociations"

  private var layouts: [String: SpaceDisplayLayout]
  private var lastSeenDisplay: [String: String]
  private var workspaceLayouts: [String: WorkspaceDisplayLayout]
  private var workspaceBySpaceUUID: [String: String]

  public init(defaults: UserDefaults = .standard, spaceManager: SpaceManager) {
    self.defaults = defaults
    self.spaceManager = spaceManager

    if let data = defaults.data(forKey: layoutsKey),
      let decoded = try? JSONDecoder().decode([String: SpaceDisplayLayout].self, from: data)
    {
      self.layouts = decoded
    } else {
      self.layouts = [:]
    }

    self.lastSeenDisplay = (defaults.dictionary(forKey: lastDisplayKey) as? [String: String]) ?? [:]

    if let data = defaults.data(forKey: workspaceLayoutsKey),
      let decoded = try? JSONDecoder().decode([String: WorkspaceDisplayLayout].self, from: data)
    {
      self.workspaceLayouts = decoded
    } else {
      self.workspaceLayouts = [:]
    }

    self.workspaceBySpaceUUID =
      (defaults.dictionary(forKey: workspaceAssociationsKey) as? [String: String]) ?? [:]
  }

  // MARK: - Persistence

  public func layout(spaceUUID: String, displayUUID: String) -> SpaceDisplayLayout? {
    layouts[Self.key(spaceUUID, displayUUID)]
  }

  public func workspaceLayout(
    workspaceID: String, displayUUID: String
  ) -> WorkspaceDisplayLayout? {
    workspaceLayouts[Self.key(workspaceID, displayUUID)]
  }

  /// Associates the persisted workspace with its current macOS Space. Existing
  /// Space-keyed data is promoted the first time a workspace is associated. If
  /// the backing Space was recreated, the newest saved frame for each configured
  /// app on the same display seeds the stable workspace layout.
  /// Returns whether a layout is available for this workspace/display pair.
  @discardableResult
  public func associateWorkspace(
    id workspaceID: String,
    spaceUUID: String,
    displayUUID: String,
    bundleIDs: Set<String> = []
  ) -> Bool {
    workspaceBySpaceUUID = workspaceBySpaceUUID.filter { $0.value != workspaceID }
    workspaceBySpaceUUID[spaceUUID] = workspaceID
    defaults.set(workspaceBySpaceUUID, forKey: workspaceAssociationsKey)

    let workspaceKey = Self.key(workspaceID, displayUUID)
    if workspaceLayouts[workspaceKey] == nil {
      let migrated = migratedApps(
        spaceUUID: spaceUUID,
        displayUUID: displayUUID,
        bundleIDs: bundleIDs)
      if !migrated.apps.isEmpty {
        workspaceLayouts[workspaceKey] = WorkspaceDisplayLayout(
          workspaceID: workspaceID,
          displayUUID: displayUUID,
          apps: migrated.apps,
          capturedAt: migrated.capturedAt)
        persistWorkspaceLayouts()
        Diagnostics.log(
          "workspace-layout-restore",
          "seeded workspace layout apps=\(migrated.apps.count)")
      }
    }

    return workspaceLayouts[workspaceKey] != nil
  }

  public func setFrame(
    bundleID: String, frame: WindowFrame, spaceUUID: String, displayUUID: String
  ) {
    let key = Self.key(spaceUUID, displayUUID)
    var layout =
      layouts[key]
      ?? SpaceDisplayLayout(spaceUUID: spaceUUID, displayUUID: displayUUID)
    layout.apps[bundleID] = frame
    layout.capturedAt = Date()
    layouts[key] = layout
    persistLayouts()

    if let workspaceID = workspaceBySpaceUUID[spaceUUID] {
      setWorkspaceFrame(
        bundleID: bundleID, frame: frame,
        workspaceID: workspaceID, displayUUID: displayUUID)
    }
  }

  public func clearAll() {
    layouts = [:]
    lastSeenDisplay = [:]
    workspaceLayouts = [:]
    workspaceBySpaceUUID = [:]
    defaults.removeObject(forKey: layoutsKey)
    defaults.removeObject(forKey: lastDisplayKey)
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
  /// (Space, display) pair the window currently sits on.
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

  /// Applies the saved layout for (spaceUUID, displayUUID) to each saved app's windows
  /// **that are actually on that space**. Returns the count of windows moved.
  ///
  /// The per-window space check exists because `kAXWindowsAttribute` returns windows
  /// from every space, not just the current one (despite Apple's documentation implying
  /// otherwise — Safari, iTerm, and JetBrains IDEs all demonstrate this). Without the
  /// check, restoring a space that moved displays stamped cross-display coordinates
  /// onto other spaces' windows, physically dragging them into whatever space was
  /// active on the target display (issue #3).
  @discardableResult
  public func restore(spaceUUID: String, displayUUID: String) -> Int {
    let token = Diagnostics.beginTiming(
      "layout-restore", "restore",
      extras: ["space": spaceUUID, "display": displayUUID])
    guard let layout = layout(spaceUUID: spaceUUID, displayUUID: displayUUID) else {
      Diagnostics.endTiming(token, outcome: "no-layout-for-pair")
      return 0
    }
    let result = apply(
      apps: layout.apps,
      targetSpaceUUID: spaceUUID,
      displayUUID: displayUUID,
      requestedBundleIDs: nil)
    Diagnostics.endTiming(
      token,
      outcome:
        "moved=\(result.movedWindows) pending=\(result.pendingBundleIDs.count)")
    return result.movedWindows
  }

  /// Applies a stable workspace layout to windows on the workspace's current
  /// backing Space. `requestedBundleIDs` lets retry callers limit subsequent
  /// attempts to apps whose windows were not ready yet.
  public func restoreWorkspace(
    workspaceID: String,
    targetSpaceUUID: String,
    displayUUID: String,
    requestedBundleIDs: Set<String>? = nil
  ) -> WorkspaceLayoutRestoreAttempt {
    let token = Diagnostics.beginTiming(
      "workspace-layout-restore", "attempt",
      extras: [
        "workspace": workspaceID,
        "space": targetSpaceUUID,
        "display": displayUUID,
      ])
    guard let layout = workspaceLayout(workspaceID: workspaceID, displayUUID: displayUUID)
    else {
      let result = WorkspaceLayoutRestoreAttempt(
        hasLayout: false, movedWindows: 0,
        restoredBundleIDs: [], pendingBundleIDs: [])
      Diagnostics.endTiming(token, outcome: "no-layout-for-workspace-display")
      return result
    }

    let result = apply(
      apps: layout.apps,
      targetSpaceUUID: targetSpaceUUID,
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

  private func persistWorkspaceLayouts() {
    if let data = try? JSONEncoder().encode(workspaceLayouts) {
      defaults.set(data, forKey: workspaceLayoutsKey)
    }
  }

  private func migratedApps(
    spaceUUID: String,
    displayUUID: String,
    bundleIDs: Set<String>
  ) -> (apps: [String: WindowFrame], capturedAt: Date) {
    let currentLayout = layout(spaceUUID: spaceUUID, displayUUID: displayUUID)
    let requestedBundleIDs =
      bundleIDs.isEmpty ? Set(currentLayout?.apps.keys.map { $0 } ?? []) : bundleIDs
    var apps = currentLayout?.apps.filter { requestedBundleIDs.contains($0.key) } ?? [:]
    var capturedAt = apps.isEmpty ? Date.distantPast : currentLayout?.capturedAt ?? .distantPast

    for bundleID in requestedBundleIDs where apps[bundleID] == nil {
      let candidates = layouts.values.filter {
        $0.displayUUID == displayUUID && $0.apps[bundleID] != nil
      }
      guard
        let latest = candidates.max(by: { $0.capturedAt < $1.capturedAt }),
        let frame = latest.apps[bundleID]
      else { continue }
      apps[bundleID] = frame
      capturedAt = max(capturedAt, latest.capturedAt)
    }

    return (apps, capturedAt)
  }

  private func setWorkspaceFrame(
    bundleID: String,
    frame: WindowFrame,
    workspaceID: String,
    displayUUID: String
  ) {
    let key = Self.key(workspaceID, displayUUID)
    var layout =
      workspaceLayouts[key]
      ?? WorkspaceDisplayLayout(workspaceID: workspaceID, displayUUID: displayUUID)
    layout.apps[bundleID] = frame
    layout.capturedAt = Date()
    workspaceLayouts[key] = layout
    persistWorkspaceLayouts()
  }

  private func apply(
    apps: [String: WindowFrame],
    targetSpaceUUID: String,
    displayUUID: String,
    requestedBundleIDs: Set<String>?
  ) -> WorkspaceLayoutRestoreAttempt {
    let availableBundleIDs = Set(apps.keys)
    let candidateBundleIDs =
      requestedBundleIDs.map { $0.intersection(availableBundleIDs) } ?? availableBundleIDs
    var pendingBundleIDs = candidateBundleIDs

    guard let screen = spaceballsScreen(forDisplayUUID: displayUUID) else {
      Diagnostics.log("layout-restore", "display not attached")
      return WorkspaceLayoutRestoreAttempt(
        hasLayout: true, movedWindows: 0,
        restoredBundleIDs: [], pendingBundleIDs: pendingBundleIDs)
    }
    guard let targetSpaceID = spaceID(forUUID: targetSpaceUUID) else {
      Diagnostics.log("layout-restore", "target Space UUID unresolved")
      return WorkspaceLayoutRestoreAttempt(
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

    return WorkspaceLayoutRestoreAttempt(
      hasLayout: true,
      movedWindows: movedWindows,
      restoredBundleIDs: restoredBundleIDs,
      pendingBundleIDs: pendingBundleIDs)
  }

  private static func key(_ identity: String, _ displayUUID: String) -> String {
    "\(identity)|\(displayUUID)"
  }
}
