import SpaceballsCore
import SpaceballsGUILib
import SwiftUI

struct TimingPane: View {
  @ObservedObject var settings: AppSettings

  private static let range: ClosedRange<Double> = 0.0...2.0
  private static let defaults = SpaceMoveTiming()

  var body: some View {
    Form {
      Section("Mission Control Timing") {
        Text(
          "Pauses used while driving Mission Control — moving Spaces, ejecting, and "
            + "restoring. Lower is faster; too low and drags can misfire (a tile snaps "
            + "back to its source). The defaults already sit near the practical floor."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        timingRow(
          "After activating a Space",
          description: "A Space can't be moved while it's the active one, so Spaceballs "
            + "first activates another Space on that display. This is the pause after "
            + "that activation, before Mission Control reopens.",
          value: $settings.timingSpaceSwitchSettle)

        timingRow(
          "After dropping a Space",
          description: "Pause after a dragged Space is released on its destination "
            + "display, giving Mission Control a moment to register the drop.",
          value: $settings.timingDropSettle)

        timingRow(
          "Before the next drag",
          description: "Extra pause before picking up the next Space when several are "
            + "moved in one pass (eject and restore).",
          value: $settings.timingBetweenDrags)
      }

      Section {
        Button("Restore Defaults") {
          settings.timingSpaceSwitchSettle = Self.defaults.preSwitchSettle
          settings.timingDropSettle = Self.defaults.dropSettle
          settings.timingBetweenDrags = Self.defaults.interDragPause
        }
        .disabled(
          settings.timingSpaceSwitchSettle == Self.defaults.preSwitchSettle
            && settings.timingDropSettle == Self.defaults.dropSettle
            && settings.timingBetweenDrags == Self.defaults.interDragPause)
      }
    }
    .formStyle(.grouped)
  }

  private func timingRow(
    _ label: String, description: String, value: Binding<Double>
  ) -> some View {
    // Typed values clamp to the slider's range on commit.
    let clamped = Binding(
      get: { value.wrappedValue },
      set: { value.wrappedValue = min(max($0, Self.range.lowerBound), Self.range.upperBound) }
    )
    return LabeledContent {
      HStack(spacing: 8) {
        Slider(value: clamped, in: Self.range)
          .frame(width: 160)
        TextField(
          "", value: clamped,
          format: .number.precision(.fractionLength(2))
        )
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.trailing)
        .frame(width: 56)
        Text("s")
          .foregroundStyle(.secondary)
      }
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(label)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
