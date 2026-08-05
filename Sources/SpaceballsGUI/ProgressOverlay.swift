import Cocoa
import SpaceballsGUILib
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
final class ProgressOverlay: SpaceTransferOverlayPresenting {
  private var panels: [NSPanel] = []

  func show(message: String, subtitle: String? = nil, showsSpinner: Bool = true) {
    performOnMain { [self] in
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
    performOnMain { [self] in
      guard !panels.isEmpty else { return }
      for panel in panels {
        panel.contentView = NSHostingView(
          rootView: ProgressOverlayView(
            message: message, subtitle: subtitle, showsSpinner: showsSpinner))
      }
    }
  }

  func dismiss() {
    performOnMain { [self] in
      dismissPanels()
    }
  }

  /// Fades every panel out over `duration`, then removes them. A show()
  /// arriving mid-fade takes over cleanly: it builds fresh panels while the
  /// old ones finish fading on their own.
  func dismiss(fadingOver duration: TimeInterval) {
    performOnMain { [self] in
      let fading = panels
      panels.removeAll()
      guard !fading.isEmpty else { return }
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = duration
          for panel in fading {
            panel.animator().alphaValue = 0
          }
        },
        completionHandler: {
          for panel in fading {
            panel.orderOut(nil)
            panel.alphaValue = 1
          }
        })
    }
  }

  private func dismissPanels() {
    for panel in panels {
      panel.orderOut(nil)
    }
    panels.removeAll()
  }

  /// Eject and restore begin on the main thread. Present synchronously there
  /// so Mission Control automation cannot race ahead of panel creation; keep
  /// background callers safe by hopping them onto the main queue.
  private func performOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
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
