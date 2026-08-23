import CoreGraphics
import Foundation
import SpaceballsCore

// MARK: - Enums

public enum AppColorScheme: String, CaseIterable, Identifiable {
  case auto
  case light
  case dark

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .auto: "Auto"
    case .light: "Light"
    case .dark: "Dark"
    }
  }
}

public enum PanelDisplay: String, CaseIterable, Identifiable {
  case active
  case primary
  case all

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .active: "Active"
    case .primary: "Primary"
    case .all: "All"
    }
  }

  public var description: String {
    switch self {
    case .active: "Display with keyboard focus"
    case .primary: "Display with the menu bar"
    case .all: "Show on every connected display"
    }
  }
}

public enum SpaceSortOrder: String, CaseIterable, Identifiable {
  case mru
  case desktopNumber
  case alphabetical

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .mru: "Most Recently Active"
    case .desktopNumber: "Desktop Ordinal"
    case .alphabetical: "Desktop Name"
    }
  }
}

// MARK: - Settings Store

public final class AppSettings: ObservableObject {
  private let defaults: UserDefaults

  @Published public var showAppIcons: Bool {
    didSet { defaults.set(showAppIcons, forKey: "showAppIcons") }
  }

  @Published public var showCurrentBadge: Bool {
    didSet { defaults.set(showCurrentBadge, forKey: "showCurrentBadge") }
  }

  @Published public var colorScheme: AppColorScheme {
    didSet { defaults.set(colorScheme.rawValue, forKey: "colorScheme") }
  }

  @Published public var textSize: Double {
    didSet { defaults.set(textSize, forKey: "textSize") }
  }

  @Published public var panelDisplay: PanelDisplay {
    didSet { defaults.set(panelDisplay.rawValue, forKey: "panelDisplay") }
  }

  @Published public var filterSpacesByDisplay: Bool {
    didSet { defaults.set(filterSpacesByDisplay, forKey: "filterSpacesByDisplay") }
  }

  @Published public var showDisplayBadge: Bool {
    didSet { defaults.set(showDisplayBadge, forKey: "showDisplayBadge") }
  }

  @Published public var showEmptySpaces: Bool {
    didSet { defaults.set(showEmptySpaces, forKey: "showEmptySpaces") }
  }

  @Published public var spaceSortOrder: SpaceSortOrder {
    didSet { defaults.set(spaceSortOrder.rawValue, forKey: "spaceSortOrder") }
  }

  @Published public var workspaces: [WorkspaceConfig] {
    didSet {
      if let data = try? JSONEncoder().encode(workspaces) {
        defaults.set(data, forKey: "workspaces")
      }
    }
  }

  /// Backward-compatible accessor for space names only.
  public var customSpaceNames: [String] {
    get { workspaces.map(\.name) }
    set {
      // Update names in-place, preserving launchers; add/remove as needed
      var updated = workspaces
      while updated.count < newValue.count {
        updated.append(WorkspaceConfig())
      }
      while updated.count > newValue.count {
        updated.removeLast()
      }
      for i in newValue.indices {
        updated[i].name = newValue[i]
      }
      workspaces = updated
    }
  }

  @Published public var excludedBundleIDs: Set<String> {
    didSet { defaults.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs") }
  }

  @Published public var keyBindings: KeyBindings {
    didSet {
      if let data = try? JSONEncoder().encode(keyBindings) {
        defaults.set(data, forKey: "keyBindings")
      }
    }
  }

  // MARK: - Resize Grid Settings

  @Published public var resizeGridColumns: Int {
    didSet { defaults.set(resizeGridColumns, forKey: "resizeGridColumns") }
  }

  @Published public var resizeGridRows: Int {
    didSet { defaults.set(resizeGridRows, forKey: "resizeGridRows") }
  }

  @Published public var resizeMargins: Double {
    didSet { defaults.set(resizeMargins, forKey: "resizeMargins") }
  }

  @Published public var resizePresets: [ResizePreset] {
    didSet {
      if let data = try? JSONEncoder().encode(resizePresets) {
        defaults.set(data, forKey: "resizePresets")
      }
    }
  }

  // MARK: - Window Layout Memory

  @Published public var rememberWindowLayouts: Bool {
    didSet { defaults.set(rememberWindowLayouts, forKey: "rememberWindowLayouts") }
  }

  // MARK: - Cursor Warp

  /// When on (default off), activating a window warps the cursor onto it so
  /// it's easy to locate — across displays or across a very large one. The
  /// cursor stays put when it's already over the window; activating an empty
  /// Space on another display recenters the cursor on that display.
  @Published public var warpCursorOnActivation: Bool {
    didSet { defaults.set(warpCursorOnActivation, forKey: "warpCursorOnActivation") }
  }

  // MARK: - Move Activation

  /// When on (default), a window moved to another Space — or a Space moved to
  /// another display — is activated after the move: the target Space becomes
  /// current and a moved window is brought to front. When off, moves are pure
  /// layout surgery and the user's current view stays put.
  @Published public var activateMovedItem: Bool {
    didSet { defaults.set(activateMovedItem, forKey: "activateMovedItem") }
  }

  /// Mission Control timing knobs (seconds) — see SpaceMoveTiming in Core.
  @Published public var timingSpaceSwitchSettle: Double {
    didSet { defaults.set(timingSpaceSwitchSettle, forKey: "timingSpaceSwitchSettle") }
  }

  @Published public var timingDropSettle: Double {
    didSet { defaults.set(timingDropSettle, forKey: "timingDropSettle") }
  }

  @Published public var timingBetweenDrags: Double {
    didSet { defaults.set(timingBetweenDrags, forKey: "timingBetweenDrags") }
  }

  /// The timing knobs bridged into Core's config type.
  public var moveTiming: SpaceMoveTiming {
    SpaceMoveTiming(
      preSwitchSettle: timingSpaceSwitchSettle,
      dropSettle: timingDropSettle,
      interDragPause: timingBetweenDrags)
  }

  // MARK: - Remote Input Capture

  /// When on (default off), the keyboard event tap listens at session level
  /// (`.cgSessionEventTap`) instead of HID level, so it also sees synthetic
  /// keyboard events injected by remote-control apps (Jump Desktop, Screen
  /// Sharing, VNC) — those enter the event stream below the HID tap point
  /// and are invisible to the default tap. Off by default: HID level is the
  /// long-verified configuration, and session level changes where Spaceballs
  /// sits relative to other apps' taps.
  @Published public var captureRemoteInput: Bool {
    didSet { defaults.set(captureRemoteInput, forKey: "captureRemoteInput") }
  }

  /// The tap point the keyboard interceptor should use.
  public var eventTapLocation: CGEventTapLocation {
    captureRemoteInput ? .cgSessionEventTap : .cghidEventTap
  }

  // MARK: - Diagnostics

  /// Master switch. When off, `Diagnostics.log(...)` calls are no-ops. Default off.
  /// Delegates persistence to `Diagnostics` (shared CLI/GUI suite) — do NOT store in the
  /// injected `defaults`: the CLI runs in a different preferences domain and would never
  /// see a value written there.
  @Published public var diagnosticsEnabled: Bool {
    didSet { Diagnostics.enabled = diagnosticsEnabled }
  }

  /// When true, window titles are replaced with `<redacted>` in log output. For users who
  /// want to share logs publicly without leaking what they were working on.
  /// Same shared-suite delegation as `diagnosticsEnabled`.
  @Published public var diagnosticsRedactWindowTitles: Bool {
    didSet { Diagnostics.redactWindowTitles = diagnosticsRedactWindowTitles }
  }

  /// Transient flag — not persisted. Disables the event tap while recording a shortcut.
  @Published public var isRecordingShortcut = false

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    defaults.register(defaults: [
      "showAppIcons": true,
      "showCurrentBadge": true,
      "colorScheme": AppColorScheme.auto.rawValue,
      "textSize": 13.0,
      "panelDisplay": PanelDisplay.active.rawValue,
      "filterSpacesByDisplay": false,
      "showDisplayBadge": true,
      "showEmptySpaces": true,
      "spaceSortOrder": SpaceSortOrder.mru.rawValue,
      "resizeGridColumns": 12,
      "resizeGridRows": 12,
      "resizeMargins": 0.0,
      "rememberWindowLayouts": true,
      "warpCursorOnActivation": false,
      "activateMovedItem": true,
      "captureRemoteInput": false,
      "timingSpaceSwitchSettle": 0.25,
      "timingDropSettle": 0.2,
      "timingBetweenDrags": 0.15,
    ])

    self.showAppIcons = defaults.bool(forKey: "showAppIcons")
    self.showCurrentBadge = defaults.bool(forKey: "showCurrentBadge")
    self.colorScheme =
      AppColorScheme(rawValue: defaults.string(forKey: "colorScheme") ?? "") ?? .auto
    self.textSize = defaults.double(forKey: "textSize")
    self.panelDisplay =
      PanelDisplay(rawValue: defaults.string(forKey: "panelDisplay") ?? "") ?? .active
    self.filterSpacesByDisplay = defaults.bool(forKey: "filterSpacesByDisplay")
    self.showDisplayBadge = defaults.bool(forKey: "showDisplayBadge")
    self.showEmptySpaces = defaults.bool(forKey: "showEmptySpaces")
    self.spaceSortOrder =
      SpaceSortOrder(rawValue: defaults.string(forKey: "spaceSortOrder") ?? "") ?? .mru
    self.warpCursorOnActivation = defaults.bool(forKey: "warpCursorOnActivation")
    self.activateMovedItem = defaults.bool(forKey: "activateMovedItem")
    self.captureRemoteInput = defaults.bool(forKey: "captureRemoteInput")
    self.timingSpaceSwitchSettle = defaults.double(forKey: "timingSpaceSwitchSettle")
    self.timingDropSettle = defaults.double(forKey: "timingDropSettle")
    self.timingBetweenDrags = defaults.double(forKey: "timingBetweenDrags")

    // Load workspaces (with migration from old customSpaceNames format)
    if let data = defaults.data(forKey: "workspaces"),
      let decoded = try? JSONDecoder().decode([WorkspaceConfig].self, from: data)
    {
      self.workspaces = decoded
    } else if let oldNames = defaults.stringArray(forKey: "customSpaceNames"), !oldNames.isEmpty {
      let migrated = oldNames.map { WorkspaceConfig(name: $0) }
      self.workspaces = migrated
      // didSet doesn't fire during init, so persist explicitly
      if let data = try? JSONEncoder().encode(migrated) {
        defaults.set(data, forKey: "workspaces")
      }
      defaults.removeObject(forKey: "customSpaceNames")
    } else {
      self.workspaces = []
    }

    self.excludedBundleIDs = Set(defaults.stringArray(forKey: "excludedBundleIDs") ?? [])

    if let data = defaults.data(forKey: "keyBindings"),
      let decoded = try? JSONDecoder().decode(KeyBindings.self, from: data)
    {
      self.keyBindings = decoded
    } else {
      self.keyBindings = KeyBindings()
    }

    // Resize grid settings
    let gridCols = defaults.integer(forKey: "resizeGridColumns")
    let gridRows = defaults.integer(forKey: "resizeGridRows")
    self.resizeGridColumns = gridCols
    self.resizeGridRows = gridRows
    self.resizeMargins = defaults.double(forKey: "resizeMargins")

    if let data = defaults.data(forKey: "resizePresets"),
      let decoded = try? JSONDecoder().decode([ResizePreset].self, from: data)
    {
      self.resizePresets = decoded
    } else {
      self.resizePresets = ResizePreset.defaultPresets(
        gridColumns: gridCols, gridRows: gridRows)
    }

    self.rememberWindowLayouts = defaults.bool(forKey: "rememberWindowLayouts")
    self.diagnosticsEnabled = Diagnostics.enabled
    self.diagnosticsRedactWindowTitles = Diagnostics.redactWindowTitles
  }

  /// Icon size proportional to text size (20px at 13pt text).
  public var iconSize: CGFloat {
    CGFloat(round(textSize * 20.0 / 13.0))
  }

}
