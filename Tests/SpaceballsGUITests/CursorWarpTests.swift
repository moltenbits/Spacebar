import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsGUILib

@Suite("Cursor Warp Planner")
struct CursorWarpPlannerTests {

  /// A window whose center is (500, 400) in global CG coordinates.
  let windowFrame = CGRect(x: 100, y: 100, width: 800, height: 600)
  let windowCenter = CGPoint(x: 500, y: 400)

  @Test("Warps onto the window when the cursor is elsewhere on the same display")
  func sameDisplayCursorOutsideWindow() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: 3000, y: 50),
        cursorDisplayUUID: "display-A", targetDisplayUUID: "display-A",
        windowFrame: windowFrame) == .windowCenter(windowCenter))
  }

  @Test("Warps onto the window when the cursor is on another display")
  func crossDisplayCursorOutsideWindow() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: -500, y: 300),
        cursorDisplayUUID: "display-B", targetDisplayUUID: "display-A",
        windowFrame: windowFrame) == .windowCenter(windowCenter))
  }

  @Test("Leaves the cursor alone when it is already over the window")
  func cursorAlreadyOverWindow() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: 150, y: 650),
        cursorDisplayUUID: "display-A", targetDisplayUUID: "display-A",
        windowFrame: windowFrame) == nil)
  }

  @Test("Still warps onto the window when the cursor position is unknown")
  func unknownCursorPositionWithWindow() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: nil,
        cursorDisplayUUID: nil, targetDisplayUUID: "display-A",
        windowFrame: windowFrame) == .windowCenter(windowCenter))
  }

  @Test("Without a window, warps to the target display's center when the cursor is elsewhere")
  func noWindowCrossDisplay() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: 10, y: 10),
        cursorDisplayUUID: "display-A", targetDisplayUUID: "display-B",
        windowFrame: nil) == .displayCenter("display-B"))
  }

  @Test("Without a window, leaves the cursor alone on the same display")
  func noWindowSameDisplay() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: 10, y: 10),
        cursorDisplayUUID: "display-A", targetDisplayUUID: "display-A",
        windowFrame: nil) == nil)
  }

  @Test("Without a window, never warps when the cursor's display is unknown")
  func noWindowUnknownCursorDisplay() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: nil,
        cursorDisplayUUID: nil, targetDisplayUUID: "display-B",
        windowFrame: nil) == nil)
  }

  @Test("Without a window, never warps when the target display is unknown")
  func noWindowUnknownTargetDisplay() {
    #expect(
      CursorWarpPlanner.destination(
        cursorPosition: CGPoint(x: 10, y: 10),
        cursorDisplayUUID: "display-A", targetDisplayUUID: nil,
        windowFrame: nil) == nil)
  }
}

@Suite("AppSettings Cursor Warp Persistence")
struct CursorWarpSettingTests {

  @Test("warpCursorOnActivation defaults to false")
  func defaultsToOff() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let settings = AppSettings(defaults: defaults)
    #expect(!settings.warpCursorOnActivation)
    defaults.removePersistentDomain(forName: suiteName)
  }

  @Test("warpCursorOnActivation persists and loads back")
  func persistence() {
    let suiteName = "com.moltenbits.spaceballs.test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!

    let settings1 = AppSettings(defaults: defaults)
    settings1.warpCursorOnActivation = true

    let settings2 = AppSettings(defaults: defaults)
    #expect(settings2.warpCursorOnActivation)

    defaults.removePersistentDomain(forName: suiteName)
  }
}
