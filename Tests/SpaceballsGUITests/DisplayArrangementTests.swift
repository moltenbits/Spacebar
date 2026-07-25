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
