import CoreGraphics
import Foundation
import Testing

@testable import SpaceballsCore

// MARK: - Helpers

private func desktop(
  _ id: UInt64, display: String, current: Bool = false
) -> SpaceInfo {
  SpaceInfo(
    id: id, uuid: "uuid-\(id)", type: .desktop,
    displayUUID: display, isCurrent: current)
}

private func fullscreen(
  _ id: UInt64, display: String, current: Bool = false
) -> SpaceInfo {
  SpaceInfo(
    id: id, uuid: "uuid-\(id)", type: .fullscreen,
    displayUUID: display, isCurrent: current)
}

/// Display A: 1 (current), 2 — Display B: 3 (current), 4. Both current Spaces
/// are visible at once, which is the whole point of the direct path.
private let twoDisplays: [SpaceInfo] = [
  desktop(1, display: "display-A", current: true),
  desktop(2, display: "display-A"),
  desktop(3, display: "display-B", current: true),
  desktop(4, display: "display-B"),
]

/// CG-coordinate (top-left origin) visible frames. Display A is the primary
/// 1920×1080 display with a 25pt menu bar; display B is a 1440×900 display to
/// its right with a 25pt menu bar and a 60pt Dock at the bottom.
private let frames: [String: CGRect] = [
  "display-A": CGRect(x: 0, y: 25, width: 1920, height: 1055),
  "display-B": CGRect(x: 1920, y: 25, width: 1440, height: 815),
]

private func route(
  spaces: [SpaceInfo] = twoDisplays,
  windowSpaceIDs: [UInt64] = [1],
  targetSpaceID: UInt64 = 3,
  windowBounds: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
  windowIsOnscreen: Bool = true,
  displayVisibleFrames: [String: CGRect] = frames
) -> WindowMoveRoute {
  WindowMovePlanner.route(
    spaces: spaces, windowSpaceIDs: windowSpaceIDs, targetSpaceID: targetSpaceID,
    windowBounds: windowBounds, windowIsOnscreen: windowIsOnscreen,
    displayVisibleFrames: displayVisibleFrames)
}

// MARK: - Eligibility

@Suite("Window Move Planner — eligibility")
struct WindowMovePlannerEligibilityTests {

  @Test("Both Spaces visible on different displays routes direct")
  func bothVisibleRoutesDirect() {
    guard case .direct = route() else {
      Issue.record("expected .direct, got \(route())")
      return
    }
  }

  @Test("Unknown target Space falls back to Mission Control")
  func targetNotFound() {
    #expect(route(targetSpaceID: 99) == .missionControl(reason: .targetNotFound))
  }

  @Test("Fullscreen target Space falls back to Mission Control")
  func targetNotDesktop() {
    let spaces = twoDisplays + [fullscreen(90, display: "display-B", current: true)]
    #expect(
      route(spaces: spaces, targetSpaceID: 90) == .missionControl(reason: .targetNotDesktop))
  }

  @Test("Target Space that is not visible falls back to Mission Control")
  func targetNotCurrent() {
    #expect(route(targetSpaceID: 4) == .missionControl(reason: .targetNotCurrent))
  }

  @Test("Window already on the target Space requires no move")
  func alreadyOnTarget() {
    #expect(
      route(windowSpaceIDs: [3], targetSpaceID: 3)
        == .alreadyOnTarget)
    #expect(
      route(windowSpaceIDs: [4], targetSpaceID: 4, windowBounds: nil, windowIsOnscreen: false)
        == .alreadyOnTarget)
  }

  @Test("Sticky window (multiple Spaces) falls back to Mission Control")
  func stickyWindow() {
    #expect(route(windowSpaceIDs: [1, 2]) == .missionControl(reason: .stickyWindow))
  }

  @Test("Window with no known Space falls back to Mission Control")
  func sourceUnknown() {
    #expect(route(windowSpaceIDs: []) == .missionControl(reason: .sourceUnknown))
  }

  @Test("Window on a Space missing from the snapshot falls back to Mission Control")
  func sourceNotFound() {
    #expect(route(windowSpaceIDs: [77]) == .missionControl(reason: .sourceNotFound))
  }

  @Test("Window on a fullscreen source Space falls back to Mission Control")
  func sourceNotDesktop() {
    let spaces = [
      fullscreen(90, display: "display-A", current: true),
      desktop(2, display: "display-A"),
      desktop(3, display: "display-B", current: true),
    ]
    #expect(
      route(spaces: spaces, windowSpaceIDs: [90])
        == .missionControl(reason: .sourceNotDesktop))
  }

  @Test("Window whose Space is not visible falls back to Mission Control")
  func sourceNotCurrent() {
    #expect(route(windowSpaceIDs: [2]) == .missionControl(reason: .sourceNotCurrent))
  }

  @Test("Source and target on the same display cannot both be visible")
  func sameDisplay() {
    // A display shows exactly one Space, so two current Spaces on one display
    // only happens with a malformed snapshot — still decline rather than write.
    let spaces = [
      desktop(1, display: "display-A", current: true),
      desktop(2, display: "display-A", current: true),
      desktop(3, display: "display-B", current: true),
    ]
    #expect(
      route(spaces: spaces, windowSpaceIDs: [1], targetSpaceID: 2)
        == .missionControl(reason: .sameDisplay))
  }

  @Test("Offscreen window (minimized / hidden) falls back to Mission Control")
  func offscreenWindow() {
    #expect(route(windowIsOnscreen: false) == .missionControl(reason: .windowOffscreen))
  }

  @Test("Unknown window bounds fall back to Mission Control")
  func boundsUnknown() {
    #expect(route(windowBounds: nil) == .missionControl(reason: .boundsUnknown))
  }

  @Test("Missing source or target display geometry falls back to Mission Control")
  func displayFrameUnknown() {
    #expect(
      route(displayVisibleFrames: ["display-A": frames["display-A"]!])
        == .missionControl(reason: .displayFrameUnknown(displayUUID: "display-B")))
    #expect(
      route(displayVisibleFrames: ["display-B": frames["display-B"]!])
        == .missionControl(reason: .displayFrameUnknown(displayUUID: "display-A")))
  }

  @Test("Guard precedence: target checks, then window membership, then source, then geometry")
  func guardPrecedence() {
    // Target not current beats a sticky, offscreen window with unknown bounds.
    #expect(
      route(windowSpaceIDs: [1, 2], targetSpaceID: 4, windowBounds: nil, windowIsOnscreen: false)
        == .missionControl(reason: .targetNotCurrent))
    // Sticky beats offscreen + unknown bounds.
    #expect(
      route(windowSpaceIDs: [1, 2], windowBounds: nil, windowIsOnscreen: false)
        == .missionControl(reason: .stickyWindow))
    // Source not current beats offscreen + unknown bounds.
    #expect(
      route(windowSpaceIDs: [2], windowBounds: nil, windowIsOnscreen: false)
        == .missionControl(reason: .sourceNotCurrent))
    // Offscreen beats unknown bounds, which beats unknown geometry.
    #expect(
      route(windowBounds: nil, windowIsOnscreen: false, displayVisibleFrames: [:])
        == .missionControl(reason: .windowOffscreen))
    #expect(
      route(windowBounds: nil, displayVisibleFrames: [:])
        == .missionControl(reason: .boundsUnknown))
  }

  @Test("Decline reasons render as stable diagnostic tokens")
  func reasonDescriptions() {
    #expect(WindowMoveRoute.DeclineReason.targetNotCurrent.description == "target-not-current")
    #expect(WindowMoveRoute.DeclineReason.stickyWindow.description == "sticky-window")
    #expect(
      WindowMoveRoute.DeclineReason.displayFrameUnknown(displayUUID: "X").description
        == "display-frame-unknown:X")
  }
}

// MARK: - Frame mapping

@Suite("Window Move Planner — frame mapping")
struct WindowMovePlannerFrameTests {

  private func directFrame(
    windowBounds: CGRect,
    windowSpaceIDs: [UInt64] = [1],
    targetSpaceID: UInt64 = 3,
    displayVisibleFrames: [String: CGRect] = frames
  ) throws -> CGRect {
    let result = route(
      windowSpaceIDs: windowSpaceIDs, targetSpaceID: targetSpaceID,
      windowBounds: windowBounds, displayVisibleFrames: displayVisibleFrames)
    guard case .direct(let frame) = result else {
      throw TestError("expected .direct, got \(result)")
    }
    return frame
  }

  private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
  }

  @Test("Size is preserved exactly")
  func sizePreserved() throws {
    let frame = try directFrame(windowBounds: CGRect(x: 100, y: 100, width: 801, height: 599))
    #expect(frame.size == CGSize(width: 801, height: 599))
  }

  @Test("Top-left-aligned window stays top-left-aligned on the target")
  func topLeftAligned() throws {
    // Flush with display A's visible origin (0, 25).
    let frame = try directFrame(windowBounds: CGRect(x: 0, y: 25, width: 800, height: 600))
    #expect(frame.origin == CGPoint(x: 1920, y: 25))
  }

  @Test("Bottom-right-aligned window stays bottom-right-aligned on the target")
  func bottomRightAligned() throws {
    // Flush with display A's visible max corner (1920, 1080).
    let frame = try directFrame(
      windowBounds: CGRect(x: 1920 - 800, y: 1080 - 600, width: 800, height: 600))
    // Display B visible max corner is (3360, 840).
    #expect(frame.origin == CGPoint(x: 3360 - 800, y: 840 - 600))
  }

  @Test("Position is mapped proportionally over each display's movable range")
  func proportional() throws {
    // Display A movable range: x 0…1120, y 25…480. Window at exactly the midpoint.
    let frame = try directFrame(windowBounds: CGRect(x: 560, y: 252.5, width: 800, height: 600))
    // Display B movable range: x 1920…2560, y 25…240. Midpoint → (2240, 132.5) → rounded.
    #expect(frame.origin == CGPoint(x: 2240, y: 133))
  }

  @Test("Window larger than the target on one axis pins that axis only")
  func oversizedOneAxis() throws {
    // 1000pt tall window: fits display A (1055) but not display B (815).
    let frame = try directFrame(windowBounds: CGRect(x: 560, y: 50, width: 800, height: 1000))
    #expect(frame.size == CGSize(width: 800, height: 1000))
    #expect(frame.origin.y == 25)  // pinned to display B's visible top
    #expect(frame.origin.x == 2240)  // x still mapped proportionally (midpoint)
  }

  @Test("Window larger than the target on both axes pins to the target origin, unshrunk")
  func oversizedBothAxes() throws {
    let frame = try directFrame(windowBounds: CGRect(x: 10, y: 30, width: 1600, height: 1000))
    #expect(frame == CGRect(x: 1920, y: 25, width: 1600, height: 1000))
  }

  @Test("Window hanging past the source edge clamps to the target's movable range")
  func partiallyOffSource() throws {
    // Origin beyond display A's movable range (x > 1120): fraction clamps to 1.
    let frame = try directFrame(windowBounds: CGRect(x: 1500, y: 100, width: 800, height: 600))
    #expect(frame.origin.x == 2560)
    // Origin above display A's visible top: fraction clamps to 0.
    let frame2 = try directFrame(windowBounds: CGRect(x: 100, y: -40, width: 800, height: 600))
    #expect(frame2.origin.y == 25)
  }

  @Test("Window that fills the source axis lands at the target's movable origin")
  func fillsSourceAxis() throws {
    // Exactly the source visible width: no movable range on x, so fraction is 0.
    let frame = try directFrame(windowBounds: CGRect(x: 0, y: 100, width: 1920, height: 600))
    #expect(frame.origin.x == 1920)
  }

  @Test("Displays left of / above the primary (negative CG origins) map correctly")
  func negativeOrigins() throws {
    let negFrames: [String: CGRect] = [
      // Display A sits to the left of and above the primary.
      "display-A": CGRect(x: -1440, y: -500, width: 1440, height: 875),
      // Display B is the primary.
      "display-B": CGRect(x: 0, y: 25, width: 1920, height: 1055),
    ]
    // Bottom-right-aligned on A: max corner (0, 375).
    let frame = try directFrame(
      windowBounds: CGRect(x: -800, y: 375 - 600, width: 800, height: 600),
      displayVisibleFrames: negFrames)
    #expect(frame.origin == CGPoint(x: 1920 - 800, y: 1080 - 600))
  }

  @Test("Reverse direction (B → A) maps with the roles swapped")
  func reverseDirection() throws {
    // Top-left-aligned on B.
    let frame = try directFrame(
      windowBounds: CGRect(x: 1920, y: 25, width: 640, height: 480),
      windowSpaceIDs: [3], targetSpaceID: 1)
    #expect(frame.origin == CGPoint(x: 0, y: 25))
  }

  @Test("Origins are rounded to whole points")
  func rounded() throws {
    let frame = try directFrame(windowBounds: CGRect(x: 1, y: 26, width: 800, height: 600))
    #expect(frame.origin.x == frame.origin.x.rounded())
    #expect(frame.origin.y == frame.origin.y.rounded())
  }
}
