import CoreGraphics

// MARK: - Shortcut Modifier Matching

/// Exact-match modifier classification for global shortcuts.
///
/// Standard macOS shortcut matching is exact: the event's modifier set must
/// EQUAL the shortcut's, not merely contain it — Cmd+Ctrl+Q (Lock Screen)
/// must not fire a Cmd+Q shortcut. Raw `CGEventFlags` also carry bits that
/// must stay out of the comparison: Caps Lock, Fn, numeric-pad, and
/// device-dependent left/right-key bits (a physical left-Cmd press arrives
/// as 0x100008, and arrow keys always carry `.maskSecondaryFn` +
/// `.maskNumericPad`).
extension CGEventFlags {
  /// The modifier keys that participate in shortcut matching.
  public static let shortcutRelevant: CGEventFlags = [
    .maskCommand, .maskShift, .maskAlternate, .maskControl,
  ]

  /// This event's modifiers reduced to the ones shortcut matching compares.
  public var shortcutModifiers: CGEventFlags {
    intersection(.shortcutRelevant)
  }

  /// Exactly Cmd — no Shift, Option, or Control.
  public var isExactlyCommand: Bool {
    shortcutModifiers == .maskCommand
  }

  /// Exactly Cmd+Shift — no Option or Control.
  public var isExactlyCommandShift: Bool {
    shortcutModifiers == [.maskCommand, .maskShift]
  }
}
