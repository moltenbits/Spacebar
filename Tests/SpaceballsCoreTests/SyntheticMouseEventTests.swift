import CoreGraphics
import Darwin
import Testing

@testable import SpaceballsCore

@Suite("Synthetic Mouse Events")
struct SyntheticMouseEventTests {
  @Test("Synthetic mouse events use an identifiable private event source")
  func privateEventSource() throws {
    let first = try #require(
      SpaceManager.makeSyntheticMouseEvent(
        type: .leftMouseDown, at: CGPoint(x: 10, y: 20), button: .left))
    let second = try #require(
      SpaceManager.makeSyntheticMouseEvent(
        type: .leftMouseDragged, at: CGPoint(x: 20, y: 30), button: .left))

    let sourceStateID = first.getIntegerValueField(.eventSourceStateID)
    #expect(sourceStateID != 0)
    #expect(second.getIntegerValueField(.eventSourceStateID) == sourceStateID)
    #expect(first.getIntegerValueField(.eventSourceUserData) == SpaceManager.syntheticEventTag)
    #expect(first.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()))

    let source = try #require(CGEventSource(event: first))
    let dragFilter = source.getLocalEventsFilterDuringSuppressionState(
      .eventSuppressionStateRemoteMouseDrag)
    #expect(dragFilter.contains(.permitLocalKeyboardEvents))
    #expect(dragFilter.contains(.permitSystemDefinedEvents))
    #expect(!dragFilter.contains(.permitLocalMouseEvents))
  }
}
