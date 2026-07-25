import SpaceballsGUILib
import SwiftUI

struct ShortcutsPane: View {
  @ObservedObject var settings: AppSettings

  private var currentConflicts: [(ShortcutAction, ShortcutAction)] {
    settings.keyBindings.conflicts()
  }

  var body: some View {
    Form {
      Section("Keyboard Shortcuts") {
        Text(
          "All shortcuts use the ⌘ (Cmd) modifier. Navigation follows the physical display "
            + "arrangement: ↑/↓ step space by space and continue onto the display above/below, "
            + "←/→ move straight to the display in that direction, and ⇧ (Shift) with ↑/↓ jumps "
            + "a whole display. Display navigation outside move mode requires \"Only show "
            + "current display's spaces\" in Appearance."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        ForEach(ShortcutAction.allCases) { action in
          shortcutRow(for: action)
        }
      }

      if !currentConflicts.isEmpty {
        Section {
          ForEach(currentConflicts, id: \.0) { first, second in
            Label(
              "\(first.label) and \(second.label) use the same key",
              systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(.orange)
            .font(.caption)
          }
        }
      }

      Section {
        Button("Restore Defaults") {
          settings.keyBindings = KeyBindings()
        }
        .disabled(settings.keyBindings == KeyBindings())
      }
    }
    .formStyle(.grouped)
  }

  private func shortcutRow(for action: ShortcutAction) -> some View {
    LabeledContent {
      KeyRecorderView(
        keyCode: shortcutBinding(for: action),
        isRecording: $settings.isRecordingShortcut
      )
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(action.label)
        Text(action.description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func shortcutBinding(for action: ShortcutAction) -> Binding<UInt16> {
    Binding(
      get: { settings.keyBindings[action] },
      set: { settings.keyBindings[action] = $0 }
    )
  }
}
