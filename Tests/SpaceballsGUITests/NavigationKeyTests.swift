import Testing

@testable import SpaceballsGUILib

@Suite("Navigation Key Resolution")
struct NavigationKeyTests {

  private let bindings = KeyBindings()

  // Default key codes: ↓ 125, ↑ 126, → 124, ← 123.

  @Test("Plain vertical arrows navigate by space")
  func plainVerticalArrowsNavigateBySpace() {
    #expect(bindings.navigationCommand(keyCode: 125, shiftHeld: false) == .nextSpace)
    #expect(bindings.navigationCommand(keyCode: 126, shiftHeld: false) == .previousSpace)
  }

  @Test("Horizontal arrows navigate by display, Shift or not")
  func horizontalArrowsNavigateByDisplay() {
    #expect(bindings.navigationCommand(keyCode: 124, shiftHeld: false) == .display(.right))
    #expect(bindings.navigationCommand(keyCode: 124, shiftHeld: true) == .display(.right))
    #expect(bindings.navigationCommand(keyCode: 123, shiftHeld: false) == .display(.left))
    #expect(bindings.navigationCommand(keyCode: 123, shiftHeld: true) == .display(.left))
  }

  @Test("Shifted arrows navigate by display in the arrow's direction")
  func shiftedArrowsNavigateByDisplay() {
    #expect(bindings.navigationCommand(keyCode: 125, shiftHeld: true) == .display(.down))
    #expect(bindings.navigationCommand(keyCode: 124, shiftHeld: true) == .display(.right))
    #expect(bindings.navigationCommand(keyCode: 126, shiftHeld: true) == .display(.up))
    #expect(bindings.navigationCommand(keyCode: 123, shiftHeld: true) == .display(.left))
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
    // The binding slot carries the direction: nextSpace is the "down" slot.
    #expect(custom.navigationCommand(keyCode: 38, shiftHeld: true) == .display(.down))
    // 125 is no longer bound to any navigation action.
    #expect(custom.navigationCommand(keyCode: 125, shiftHeld: false) == nil)
  }

  @Test("Minimize key resolves window and Space actions from Shift")
  func minimizeKeyResolvesScope() {
    #expect(bindings.minimizeCommand(keyCode: 46, shiftHeld: false) == .window)
    #expect(bindings.minimizeCommand(keyCode: 46, shiftHeld: true) == .space)
    #expect(bindings.minimizeCommand(keyCode: 7, shiftHeld: false) == nil)
  }

  @Test("Custom minimize key resolves both scopes")
  func customMinimizeKeyResolvesScope() {
    var custom = KeyBindings()
    custom.minimizeWindow = 5

    #expect(custom.minimizeCommand(keyCode: 5, shiftHeld: false) == .window)
    #expect(custom.minimizeCommand(keyCode: 5, shiftHeld: true) == .space)
    #expect(custom.minimizeCommand(keyCode: 46, shiftHeld: false) == nil)
  }
}
