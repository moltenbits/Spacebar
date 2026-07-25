import CoreGraphics
import Testing

@testable import SpaceballsGUILib

/// A plus-shaped arrangement in AppKit (y-up) global coordinates:
///
///            ┌──────┐
///            │  up  │
///     ┌──────┼──────┼──────┐
///     │ left │center│ right│
///     └──────┼──────┼──────┘
///            │ down │
///            └──────┘
private func makePlusArrangement() -> DisplayArrangement {
  DisplayArrangement(displays: [
    .init(uuid: "center", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
    .init(uuid: "up", frame: CGRect(x: 200, y: 1080, width: 1600, height: 900)),
    .init(uuid: "down", frame: CGRect(x: 200, y: -900, width: 1600, height: 900)),
    .init(uuid: "left", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)),
    .init(uuid: "right", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
  ])
}

@Suite("Display Arrangement")
struct DisplayArrangementTests {

  @Test("Neighbors resolve in all four directions from the center")
  func neighborsFromCenter() {
    let a = makePlusArrangement()
    #expect(a.neighborUUID(of: "center", direction: .up) == "up")
    #expect(a.neighborUUID(of: "center", direction: .down) == "down")
    #expect(a.neighborUUID(of: "center", direction: .left) == "left")
    #expect(a.neighborUUID(of: "center", direction: .right) == "right")
  }

  @Test("Arms of the plus resolve back toward the center")
  func armsResolveBackToCenter() {
    let a = makePlusArrangement()
    #expect(a.neighborUUID(of: "up", direction: .down) == "center")
    #expect(a.neighborUUID(of: "down", direction: .up) == "center")
    #expect(a.neighborUUID(of: "left", direction: .right) == "center")
    #expect(a.neighborUUID(of: "right", direction: .left) == "center")
  }

  @Test("No display in a direction resolves to nil")
  func noNeighborResolvesToNil() {
    let a = makePlusArrangement()
    #expect(a.neighborUUID(of: "up", direction: .up) == nil)
    #expect(a.neighborUUID(of: "left", direction: .left) == nil)
    #expect(a.neighborUUID(of: "down", direction: .down) == nil)
    #expect(a.neighborUUID(of: "right", direction: .right) == nil)
  }

  @Test("Diagonal displays are reachable when nothing lies squarely in the direction")
  func diagonalReachable() {
    let a = makePlusArrangement()
    // From the left arm, "up" is diagonal (up-right of it) but it is the
    // only display whose center is above — it must still be reachable.
    #expect(a.neighborUUID(of: "left", direction: .up) == "up")
    #expect(a.neighborUUID(of: "left", direction: .down) == "down")
  }

  @Test("The straightest candidate beats a nearer diagonal one")
  func straightestCandidateWins() {
    // "offset" sits up-right of origin and slightly closer than "straight",
    // which is squarely to the right. Pressing right must pick "straight".
    let a = DisplayArrangement(displays: [
      .init(uuid: "origin", frame: CGRect(x: 0, y: 0, width: 1000, height: 1000)),
      .init(uuid: "straight", frame: CGRect(x: 2000, y: 0, width: 1000, height: 1000)),
      .init(uuid: "offset", frame: CGRect(x: 1000, y: 1000, width: 1000, height: 1000)),
    ])
    #expect(a.neighborUUID(of: "origin", direction: .right) == "straight")
  }

  @Test("Unknown display resolves to nil")
  func unknownDisplayResolvesToNil() {
    let a = makePlusArrangement()
    #expect(a.neighborUUID(of: "ghost", direction: .up) == nil)
  }
}

/// A real-world four-display arrangement (y-up coordinates): built-in laptop
/// at the bottom, a large landscape display above whose center sits a hair
/// (74pt) to the RIGHT of the built-in's center, and a tall portrait display
/// on each side whose centers sit far ABOVE the laptop's low center.
///
///  ┌────┐┌──────────────┐┌────┐
///  │    ││     top      ││    │
///  │left│└──────────────┘│rght│
///  │    │   ┌───────┐    │    │
///  └────┘   │builtin│    └────┘
///           └───────┘
private func makeQuadArrangement() -> DisplayArrangement {
  DisplayArrangement(displays: [
    .init(uuid: "builtin", frame: CGRect(x: 0, y: -1169, width: 1800, height: 1169)),
    .init(uuid: "top", frame: CGRect(x: -946, y: 0, width: 3840, height: 2560)),
    .init(uuid: "right", frame: CGRect(x: 2894, y: -947, width: 2160, height: 3840)),
    .init(uuid: "left", frame: CGRect(x: -3106, y: -929, width: 2160, height: 3840)),
  ])
}

@Suite("Display Arrangement — quad layout")
struct DisplayArrangementQuadTests {

  @Test("A display beside the origin beats a nearly-centered display above it")
  func sideDisplayBeatsNearlyCenteredDisplayAbove() {
    let a = makeQuadArrangement()
    // The top display's center is 74pt right of the built-in's — that must
    // not make it the "right" neighbor when a display physically clears the
    // built-in's right edge.
    #expect(a.neighborUUID(of: "builtin", direction: .right) == "right")
    #expect(a.neighborUUID(of: "builtin", direction: .left) == "left")
    #expect(a.neighborUUID(of: "builtin", direction: .up) == "top")
    #expect(a.neighborUUID(of: "builtin", direction: .down) == nil)
  }

  @Test("Half-plane fallback keeps diagonal-only neighbors reachable")
  func halfPlaneFallbackKeepsDiagonalsReachable() {
    let a = makeQuadArrangement()
    // The built-in's center doesn't clear the right portrait's bottom edge
    // (the portrait extends below it), but nothing else is downward at all —
    // the fallback tier must still find it.
    #expect(a.neighborUUID(of: "right", direction: .down) == "builtin")
    #expect(a.neighborUUID(of: "left", direction: .down) == "builtin")
  }

  @Test("Portraits resolve horizontally to the display their centers align with")
  func portraitsResolveHorizontallyToTop() {
    let a = makeQuadArrangement()
    // From a side portrait, the top landscape is the straight-across
    // neighbor (centers nearly level); the laptop sits far below.
    #expect(a.neighborUUID(of: "right", direction: .left) == "top")
    #expect(a.neighborUUID(of: "left", direction: .right) == "top")
    #expect(a.neighborUUID(of: "top", direction: .right) == "right")
    #expect(a.neighborUUID(of: "top", direction: .left) == "left")
    #expect(a.neighborUUID(of: "top", direction: .down) == "builtin")
  }
}
