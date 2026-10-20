import AppKit
import QuartzCore

/// Keeps native frame animation separate from editor ownership and persistence.
/// State tests can explicitly finish transitions without a compositor callback.
protocol WindowAnimating {
  func resize(
    _ window: NSWindow, to frame: NSRect, duration: TimeInterval,
    completion: @escaping () -> Void)
}

struct AppKitWindowAnimator: WindowAnimating {
  func resize(
    _ window: NSWindow, to frame: NSRect, duration: TimeInterval,
    completion: @escaping () -> Void
  ) {
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration =
          NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        window.animator().setFrame(frame, display: true)
      }, completionHandler: completion)
  }
}
