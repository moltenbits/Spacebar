import SpaceballsCore

@testable import SpaceballsGUILib

struct StubSwitcherDisplayContextProvider: SwitcherDisplayContextProviding {
  let context: SwitcherDisplayContext

  func currentContext() -> SwitcherDisplayContext {
    context
  }
}

func makeTestSwitcherViewModel(
  spaceManager: SpaceManager = SpaceManager(),
  spaceNameStore: SpaceNameStoring = SpaceNameStore(),
  displayContext: SwitcherDisplayContext = SwitcherDisplayContext(
    focusedDisplayUUID: "unmatched-test-display",
    displayNamesByUUID: [:]
  )
) -> SwitcherViewModel {
  SwitcherViewModel(
    spaceManager: spaceManager,
    spaceNameStore: spaceNameStore,
    displayContextProvider: StubSwitcherDisplayContextProvider(context: displayContext)
  )
}
