import AppKit

/// Real windows and geometry, with explicit completion timing for state tests.
/// Rendering/animation tests continue to exercise the production renderer.
final class ControlledWindowAnimator: WindowAnimating {
  private var completions: [() -> Void] = []

  func resize(
    _ window: NSWindow, to frame: NSRect, duration: TimeInterval,
    completion: @escaping () -> Void
  ) {
    window.setFrame(frame, display: true)
    completions.append(completion)
  }

  func finish() {
    let pending = completions
    completions.removeAll()
    pending.forEach { $0() }
  }
}
