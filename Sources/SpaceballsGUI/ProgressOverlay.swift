import Cocoa
import SwiftUI

/// A full-screen, click-through overlay shown on EVERY display while a
/// Mission Control automation (eject/restore) drives synthetic mouse input.
/// Unmissable by design: the small StatusHUD sits below Mission Control's
/// window level and is easy to overlook, and a stray user mouse move can
/// break the drags mid-flight.
///
/// The panels sit ABOVE Mission Control (`.screenSaver` level) and MUST keep
/// `ignoresMouseEvents = true` — the synthetic drag events route to whatever
/// window is under the cursor, and an event-eating overlay would swallow
/// them. The scrim is translucent so the Mission Control ballet stays
/// visible underneath.
final class ProgressOverlay {
  private var panels: [NSPanel] = []

  func show(message: String, subtitle: String? = nil, showsSpinner: Bool = true) {
    DispatchQueue.main.async { [self] in
      dismissPanels()  // rebuild against the current screen set
      for screen in NSScreen.screens {
        let panel = NSPanel(
          contentRect: screen.frame,
          styleMask: [.borderless, .nonactivatingPanel],
          backing: .buffered,
          defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(
          rootView: ProgressOverlayView(
            message: message, subtitle: subtitle, showsSpinner: showsSpinner))
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        panels.append(panel)
      }
    }
  }

  func update(message: String, subtitle: String? = nil, showsSpinner: Bool = false) {
    DispatchQueue.main.async { [self] in
      guard !panels.isEmpty else { return }
      for panel in panels {
        panel.contentView = NSHostingView(
          rootView: ProgressOverlayView(
            message: message, subtitle: subtitle, showsSpinner: showsSpinner))
      }
    }
  }

  func dismiss() {
    DispatchQueue.main.async { [self] in
      dismissPanels()
    }
  }

  private func dismissPanels() {
    for panel in panels {
      panel.orderOut(nil)
    }
    panels.removeAll()
  }
}

private struct ProgressOverlayView: View {
  let message: String
  let subtitle: String?
  let showsSpinner: Bool

  var body: some View {
    ZStack {
      Color.black.opacity(0.35)
      VStack(spacing: 16) {
        if showsSpinner {
          ProgressView()
            .controlSize(.large)
            .tint(.white)
        }
        Text(message)
          .font(.system(size: 36, weight: .bold))
          .foregroundStyle(.white)
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
        }
      }
      .padding(48)
      .multilineTextAlignment(.center)
    }
    .ignoresSafeArea()
  }
}
