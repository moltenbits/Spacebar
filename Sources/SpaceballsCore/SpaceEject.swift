import CoreGraphics
import Foundation

/// One tile drag within a Mission Control batch session.
public struct SpaceTileDrag {
  public let sourceSpaceIndex: Int
  public let sourceScreenNumber: CGDirectDisplayID
  public let targetScreenNumber: CGDirectDisplayID

  public init(
    sourceSpaceIndex: Int, sourceScreenNumber: CGDirectDisplayID,
    targetScreenNumber: CGDirectDisplayID
  ) {
    self.sourceSpaceIndex = sourceSpaceIndex
    self.sourceScreenNumber = sourceScreenNumber
    self.targetScreenNumber = targetScreenNumber
  }
}

public struct EjectSummary {
  /// UUIDs of spaces verified to have landed on the built-in display.
  public let ejected: [String]
  /// Space IDs whose planned move did not verifiably complete.
  public let failed: [UInt64]
}

public struct SpaceRestoreSummary {
  /// UUIDs of spaces moved back to their recorded display just now.
  public let restored: [String]
  /// UUIDs still pending because their display remains disconnected.
  public let waiting: [String]
}

// MARK: - Eject / Restore

extension SpaceManager {

  /// Moves every non-Default desktop space off every external display onto
  /// the built-in display in one Mission Control session, recording each
  /// space's origin in `ejectStore` for later restore. A display whose
  /// spaces would all leave gets a Default Space created and named first.
  /// No space is activated afterwards — the built-in display's active space
  /// stays wherever it was.
  public func ejectSpaces(
    spaceNameStore: SpaceNameStoring, ejectStore: EjectRecordStoring
  ) throws -> EjectSummary {
    guard let builtinUUID = Self.builtinDisplayUUID() else {
      throw SpaceMoveError.displayNotResolvable(displayUUID: "built-in")
    }
    guard Self.ensureAccessibilityTrusted() else {
      throw SpaceMoveError.accessibilityNotTrusted
    }
    let token = Diagnostics.beginTiming("eject", "ejectSpaces")

    var plan = EjectPlanner.plan(
      spaces: getAllSpaces(), targetDisplayUUID: builtinUUID,
      names: spaceNameStore.allCustomNames())

    // Create + name a Default Space where one is missing, then re-plan
    // against the fresh space list (creation appends, so existing tile
    // indices survive — but re-planning keeps one source of truth).
    if !plan.displaysNeedingDefault.isEmpty {
      for displayUUID in plan.displaysNeedingDefault {
        try createDefaultSpace(on: displayUUID, spaceNameStore: spaceNameStore)
      }
      plan = EjectPlanner.plan(
        spaces: getAllSpaces(), targetDisplayUUID: builtinUUID,
        names: spaceNameStore.allCustomNames())
      guard plan.displaysNeedingDefault.isEmpty else {
        Diagnostics.endTiming(token, outcome: "default-creation-failed")
        throw SpaceMoveError.spaceCreationFailed(
          displayUUID: plan.displaysNeedingDefault[0])
      }
    }

    let verified = executePlannedMoves(preSwitches: plan.preSwitches, moves: plan.moves)
    for move in verified {
      ejectStore.recordEjection(
        spaceUUID: move.spaceUUID, originalDisplayUUID: move.sourceDisplayUUID)
    }
    let verifiedIDs = Set(verified.map(\.spaceID))
    let summary = EjectSummary(
      ejected: verified.map(\.spaceUUID),
      failed: plan.moves.map(\.spaceID).filter { !verifiedIDs.contains($0) })
    Diagnostics.endTiming(
      token, outcome: "ejected=\(summary.ejected.count) failed=\(summary.failed.count)")
    return summary
  }

  /// Moves previously ejected spaces back to their recorded displays (those
  /// currently connected) in one Mission Control session, clearing records
  /// as they complete. Records whose display is still disconnected are kept;
  /// records whose space no longer exists are dropped. No space is activated.
  public func restoreEjectedSpaces(ejectStore: EjectRecordStoring) throws -> SpaceRestoreSummary {
    let pending = ejectStore.pendingEjections()
    guard !pending.isEmpty else { return SpaceRestoreSummary(restored: [], waiting: []) }
    guard Self.ensureAccessibilityTrusted() else {
      throw SpaceMoveError.accessibilityNotTrusted
    }
    let token = Diagnostics.beginTiming("eject", "restoreEjectedSpaces")

    let plan = RestorePlanner.plan(spaces: getAllSpaces(), pending: pending)
    for spaceUUID in plan.stale + plan.completed {
      ejectStore.clearEjection(spaceUUID: spaceUUID)
    }

    let restored = executePlannedMoves(preSwitches: plan.preSwitches, moves: plan.moves)
    for move in restored {
      ejectStore.clearEjection(spaceUUID: move.spaceUUID)
    }
    let summary = SpaceRestoreSummary(restored: restored.map(\.spaceUUID), waiting: plan.waiting)
    Diagnostics.endTiming(
      token, outcome: "restored=\(summary.restored.count) waiting=\(summary.waiting.count)")
    return summary
  }

  /// Pre-switches displays off the spaces about to move, runs the batch of
  /// tile drags in one Mission Control session, and CGS-verifies each drop.
  /// Returns the moves whose spaces verifiably landed on their targets.
  private func executePlannedMoves(
    preSwitches: [EjectPlanner.PreSwitch], moves: [EjectPlanner.Move]
  ) -> [EjectPlanner.Move] {
    guard !moves.isEmpty else { return [] }

    // MC refuses to drag a display's current space, so FIRST park each
    // affected display on a staying space. switchToSpace presses a tile in
    // its own Mission Control appearance — and the awake notification that
    // opens MC is a TOGGLE — so the switches run strictly one at a time,
    // each verified via CGS and waited out until Mission Control is fully
    // gone, before the next switch (or the drag session) opens MC again.
    for preSwitch in preSwitches {
      guard let screen = Self.displayIDForUUID(preSwitch.displayUUID) else { continue }
      switchToSpace(spaceIndex: preSwitch.toSpaceIndex, screenNumber: screen)
      let switched = poll(timeout: 3.0) {
        self.getAllSpaces().first(where: {
          $0.displayUUID == preSwitch.displayUUID && $0.isCurrent
        })?.id == preSwitch.toSpaceID
      }
      if !switched {
        Diagnostics.log(
          "eject", "pre-switch of \(preSwitch.displayUUID) not confirmed — continuing")
      }
      Self.awaitMissionControlDismissed(timeout: 2.0)
      // Let the space-switch animation finish before the next MC round.
      Thread.sleep(forTimeInterval: 0.8)
    }

    var drags: [SpaceTileDrag] = []
    var dragMoves: [EjectPlanner.Move] = []
    for move in moves {
      guard let sourceScreen = Self.displayIDForUUID(move.sourceDisplayUUID),
        let targetScreen = Self.displayIDForUUID(move.targetDisplayUUID)
      else { continue }
      drags.append(
        SpaceTileDrag(
          sourceSpaceIndex: move.sourceIndex,
          sourceScreenNumber: sourceScreen, targetScreenNumber: targetScreen))
      dragMoves.append(move)
    }

    // Each completed drop shifts the tiles remaining in its source bar, so
    // every drag re-derives its tile index from a fresh CGS read. When CGS
    // reflects drops live, that's the true post-shift position; when it
    // lags, the read returns the planned index — which the DESCENDING
    // per-display order keeps correct regardless.
    let attemptedIndices = moveSpacesInMCBatch(drags) { dragIndex in
      let move = dragMoves[dragIndex]
      let spaces = self.getAllSpaces()
      guard
        let space = spaces.first(where: { $0.id == move.spaceID }),
        space.displayUUID == move.sourceDisplayUUID
      else { return nil }  // already landed elsewhere, or gone — skip
      return
        spaces
        .filter { $0.type == .desktop && $0.displayUUID == move.sourceDisplayUUID }
        .firstIndex(where: { $0.id == move.spaceID })
    }
    let attempted = attemptedIndices.map { dragMoves[$0] }

    // The drops animate before CGS reflects the new topology — poll until
    // every attempted move is visible (or the scaled timeout elapses), then
    // report everything that actually landed, attempted or not.
    _ = poll(timeout: 2.0 + 0.5 * Double(attempted.count)) {
      let spaces = self.getAllSpaces()
      return attempted.allSatisfy { move in
        spaces.first(where: { $0.id == move.spaceID })?.displayUUID == move.targetDisplayUUID
      }
    }
    let finalSpaces = getAllSpaces()
    return moves.filter { move in
      finalSpaces.first(where: { $0.id == move.spaceID })?.displayUUID
        == move.targetDisplayUUID
    }
  }

  /// Synchronously creates one space on `displayUUID` and names it
  /// "Default Space" (identified by UUID diff, matching the sibling-creation
  /// flow in moveSpaceToDisplay).
  private func createDefaultSpace(
    on displayUUID: String, spaceNameStore: SpaceNameStoring
  ) throws {
    guard let screen = Self.displayIDForUUID(displayUUID) else {
      throw SpaceMoveError.displayNotResolvable(displayUUID: displayUUID)
    }
    let before = Set(getAllSpaces().map(\.uuid))

    let semaphore = DispatchSemaphore(value: 0)
    var createResult: Result<Int, SpaceCreateError> = .failure(.missionControlNotFound)
    createSpace(count: 1, screenNumber: screen) { result in
      createResult = result
      semaphore.signal()
    }
    semaphore.wait()

    let created =
      (try? createResult.get()) == 1
      && poll(timeout: 3.0) {
        !Self.newlyCreatedSpaces(before: before, after: self.getAllSpaces()).isEmpty
      }
    guard created else {
      throw SpaceMoveError.spaceCreationFailed(displayUUID: displayUUID)
    }
    for space in Self.newlyCreatedSpaces(before: before, after: getAllSpaces()) {
      spaceNameStore.setCustomName(SpaceNameStore.defaultSpaceName, forSpaceUUID: space.uuid)
    }
  }
}
