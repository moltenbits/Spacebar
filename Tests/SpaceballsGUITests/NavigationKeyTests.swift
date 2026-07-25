import Testing

@testable import SpaceballsGUILib

@Suite("Navigation Key Resolution")
struct NavigationKeyTests {

  private let bindings = KeyBindings()

  // Default key codes: ↓ 125, ↑ 126, → 124, ← 123.

  @Test("Plain arrows all navigate by space")
  func plainArrowsNavigateBySpace() {
    #expect(bindings.navigationCommand(keyCode: 125, shiftHeld: false) == .nextSpace)
    #expect(bindings.navigationCommand(keyCode: 124, shiftHeld: false) == .nextSpace)
    #expect(bindings.navigationCommand(keyCode: 126, shiftHeld: false) == .previousSpace)
    #expect(bindings.navigationCommand(keyCode: 123, shiftHeld: false) == .previousSpace)
  }

  @Test("Shifted arrows all navigate by display")
  func shiftedArrowsNavigateByDisplay() {
    #expect(bindings.navigationCommand(keyCode: 125, shiftHeld: true) == .nextDisplay)
    #expect(bindings.navigationCommand(keyCode: 124, shiftHeld: true) == .nextDisplay)
    #expect(bindings.navigationCommand(keyCode: 126, shiftHeld: true) == .previousDisplay)
    #expect(bindings.navigationCommand(keyCode: 123, shiftHeld: true) == .previousDisplay)
  }

  @Test("Non-navigation keys resolve to nothing")
  func nonNavigationKeysResolveToNil() {
    // Tab (48) and Escape (53) are bound to other actions.
    #expect(bindings.navigationCommand(keyCode: 48, shiftHeld: false) == nil)
    #expect(bindings.navigationCommand(keyCode: 48, shiftHeld: true) == nil)
    #expect(bindings.navigationCommand(keyCode: 53, shiftHeld: false) == nil)
  }

  @Test("Custom bindings are honored and defaults released")
  func customBindingsHonored() {
    var custom = KeyBindings()
    custom.nextSpace = 38  // J
    #expect(custom.navigationCommand(keyCode: 38, shiftHeld: false) == .nextSpace)
    #expect(custom.navigationCommand(keyCode: 38, shiftHeld: true) == .nextDisplay)
    // 125 is no longer bound to any navigation action.
    #expect(custom.navigationCommand(keyCode: 125, shiftHeld: false) == nil)
  }
}
