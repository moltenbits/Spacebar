import CoreGraphics
import Testing

@testable import SpaceballsGUILib

// MARK: - Shortcut Modifier Matching Tests

@Suite("Shortcut Modifier Matching")
struct ShortcutModifiersTests {
  @Test("Exactly Cmd matches Cmd alone")
  func exactCommand() {
    let flags: CGEventFlags = [.maskCommand]
    #expect(flags.isExactlyCommand)
    #expect(!flags.isExactlyCommandShift)
  }

  @Test("Exactly Cmd+Shift matches Cmd+Shift alone")
  func exactCommandShift() {
    let flags: CGEventFlags = [.maskCommand, .maskShift]
    #expect(flags.isExactlyCommandShift)
    #expect(!flags.isExactlyCommand)
  }

  @Test("Extra Option modifier defeats both exact matches")
  func optionDefeatsMatch() {
    let cmdOpt: CGEventFlags = [.maskCommand, .maskAlternate]
    #expect(!cmdOpt.isExactlyCommand)
    #expect(!cmdOpt.isExactlyCommandShift)

    let cmdShiftOpt: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate]
    #expect(!cmdShiftOpt.isExactlyCommand)
    #expect(!cmdShiftOpt.isExactlyCommandShift)
  }

  @Test("Extra Control modifier defeats both exact matches (Cmd+Ctrl+Q is Lock Screen, not Quit)")
  func controlDefeatsMatch() {
    let cmdCtrl: CGEventFlags = [.maskCommand, .maskControl]
    #expect(!cmdCtrl.isExactlyCommand)
    #expect(!cmdCtrl.isExactlyCommandShift)
  }

  @Test("Shift on top of Cmd is not exactly Cmd")
  func shiftDefeatsExactCommand() {
    let flags: CGEventFlags = [.maskCommand, .maskShift]
    #expect(!flags.isExactlyCommand)
  }

  @Test("Device-dependent left/right key bits are ignored")
  func deviceBitsIgnored() {
    // Real left-Cmd keyboard events carry 0x100008, not the bare 0x100000 mask.
    let leftCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8)
    #expect(leftCmd.isExactlyCommand)

    let leftCmdLeftShift = CGEventFlags(
      rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue | 0x8 | 0x2)
    #expect(leftCmdLeftShift.isExactlyCommandShift)
  }

  @Test("Caps Lock is ignored")
  func capsLockIgnored() {
    let flags: CGEventFlags = [.maskCommand, .maskAlphaShift]
    #expect(flags.isExactlyCommand)
  }

  @Test("Fn and numeric-pad bits are ignored (arrow keys always carry them)")
  func arrowKeyBitsIgnored() {
    let cmdArrow: CGEventFlags = [.maskCommand, .maskSecondaryFn, .maskNumericPad]
    #expect(cmdArrow.isExactlyCommand)

    let cmdShiftArrow: CGEventFlags = [
      .maskCommand, .maskShift, .maskSecondaryFn, .maskNumericPad,
    ]
    #expect(cmdShiftArrow.isExactlyCommandShift)
  }

  @Test("shortcutModifiers reduces to the four compared modifiers")
  func relevantReduction() {
    let noisy: CGEventFlags = [
      .maskCommand, .maskShift, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad,
    ]
    #expect(noisy.shortcutModifiers == [.maskCommand, .maskShift])

    let plain: CGEventFlags = [.maskSecondaryFn, .maskNumericPad]
    #expect(plain.shortcutModifiers == [])

    let shiftOnly: CGEventFlags = [.maskShift, .maskAlphaShift]
    #expect(shiftOnly.shortcutModifiers == .maskShift)
  }

  @Test("No modifiers matches neither exact form")
  func noModifiers() {
    let flags: CGEventFlags = []
    #expect(!flags.isExactlyCommand)
    #expect(!flags.isExactlyCommandShift)
    #expect(flags.shortcutModifiers == [])
  }
}
