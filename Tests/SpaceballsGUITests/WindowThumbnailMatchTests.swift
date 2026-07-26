import Testing

@testable import SpaceballsCore

/// Pure matching logic for Mission Control window thumbnails.
/// `displayTitles[0]` is the source display (the one showing the window's
/// space); later arrays are other displays in search order.
@Suite("Window Thumbnail Matching")
struct WindowThumbnailMatchTests {

  @Test("An exact match is found wherever it appears")
  func exactMatchAnywhere() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [["bash", "Inbox"], ["spaceballs – SpaceManager.swift"]],
      windowTitle: "spaceballs – SpaceManager.swift")
    #expect(result?.display == 1)
    #expect(result?.index == 0)
  }

  @Test("An exact match on a later display beats an earlier substring match")
  func exactBeatsEarlierSubstring() {
    // The regression: display 0 (destination) holds ONE window whose title
    // merely contains the search string; display 1 (source) holds the real
    // window with the exact title. The old per-display loop grabbed the
    // substring match and never reached the exact one.
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [
        ["jamesdh — ~/Projects/moltenbits/spaceballs — iTerm2"],
        ["spaceballs"],
      ],
      windowTitle: "spaceballs")
    #expect(result?.display == 1)
    #expect(result?.index == 0)
  }

  @Test("With no exact match, a substring match unique to the source display wins")
  func sourceDisplaySubstringWins() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [
        ["spaceballs – EjectPlanner.swift [modified]"],
        ["jamesdh — spaceballs — iTerm2", "spaceballs — notes"],
      ],
      windowTitle: "spaceballs – EjectPlanner.swift")
    #expect(result?.display == 0)
    #expect(result?.index == 0)
  }

  @Test("With no source-display match, a globally unique substring match wins")
  func globallyUniqueSubstringWins() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [["bash", "Inbox"], ["Google", "spaceballs — notes"]],
      windowTitle: "spaceballs")
    #expect(result?.display == 1)
    #expect(result?.index == 1)
  }

  @Test("An ambiguous substring match resolves to nil")
  func ambiguousSubstringIsNil() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [["bash"], ["spaceballs — one", "spaceballs — two"]],
      windowTitle: "spaceballs")
    #expect(result == nil)
  }

  @Test("Substring matching is case-insensitive")
  func substringIsCaseInsensitive() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [["SpaceBalls — Notes"]],
      windowTitle: "spaceballs")
    #expect(result?.display == 0)
    #expect(result?.index == 0)
  }

  @Test("Duplicate exact titles resolve to the source display's thumbnail")
  func duplicateExactPrefersSourceDisplay() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [["untitled", "bash"], ["untitled"]],
      windowTitle: "untitled")
    #expect(result?.display == 0)
    #expect(result?.index == 0)
  }

  @Test("Nil titles and no match resolve to nil")
  func noMatchIsNil() {
    let result = SpaceManager.matchWindowThumbnail(
      displayTitles: [[nil, "bash"], []],
      windowTitle: "spaceballs")
    #expect(result == nil)
  }
}
