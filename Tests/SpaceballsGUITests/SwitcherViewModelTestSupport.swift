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
  minimizeWindow: @escaping (Int) throws -> Void = { _ in },
  displayContext: SwitcherDisplayContext = SwitcherDisplayContext(
    focusedDisplayUUID: "unmatched-test-display",
    displayNamesByUUID: [:]
  )
) -> SwitcherViewModel {
  SwitcherViewModel(
    spaceManager: spaceManager,
    spaceNameStore: spaceNameStore,
    minimizeWindow: minimizeWindow,
    displayContextProvider: StubSwitcherDisplayContextProvider(context: displayContext)
  )
}
