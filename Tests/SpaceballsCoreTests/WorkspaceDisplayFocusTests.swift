import CoreGraphics
import Testing

@testable import SpaceballsCore

@Suite("Workspace Display Focus")
struct WorkspaceDisplayFocusTests {
  @Test("Single-display restores and already-focused targets need no focus action")
  func skipsUnnecessaryFocus() {
    #expect(
      !SpaceManager.workspaceDisplayNeedsFocus(
        displayCount: 1, focusedWindowSpaceIDs: [], targetSpaceID: 1))
    #expect(
      !SpaceManager.workspaceDisplayNeedsFocus(
        displayCount: 2, focusedWindowSpaceIDs: [1], targetSpaceID: 1))
    #expect(
      SpaceManager.workspaceDisplayNeedsFocus(
        displayCount: 2, focusedWindowSpaceIDs: [2], targetSpaceID: 1))
    #expect(
      SpaceManager.workspaceDisplayNeedsFocus(
        displayCount: 2, focusedWindowSpaceIDs: [], targetSpaceID: 1))
    #expect(
      SpaceManager.workspaceDisplayNeedsFocus(
        displayCount: 2, focusedWindowSpaceIDs: [1, 2], targetSpaceID: 1))
  }

  @Test("Desktop focus avoids visible windows and stays on the target display")
  func avoidsWindows() throws {
    let frame = CGRect(x: 1800, y: -500, width: 1200, height: 800)
    let window = CGRect(x: 1800, y: -500, width: 900, height: 800)
    let point = try #require(
      SpaceManager.workspaceDesktopFocusPoint(in: frame, occupiedBounds: [window]))
    #expect(frame.contains(point))
    #expect(!window.contains(point))
  }

  @Test("A covered desktop never falls back to clicking through a window")
  func coveredDesktop() {
    let frame = CGRect(x: 0, y: 25, width: 1200, height: 800)
    #expect(SpaceManager.workspaceDesktopFocusPoint(in: frame, occupiedBounds: [frame]) == nil)
    #expect(SpaceManager.workspaceDesktopFocusPoint(in: .zero, occupiedBounds: []) == nil)
  }
}
