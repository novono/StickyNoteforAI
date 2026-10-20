import AppKit

/// Recent pointer movement, independent of event frequency and window position.
struct ThrowVelocity {
  private struct Sample {
    let point: NSPoint
    let time: TimeInterval
  }
  private var samples: [Sample] = []
  private var lastMovement: TimeInterval?

  mutating func add(_ point: NSPoint, at time: TimeInterval) {
    guard time.isFinite, point.x.isFinite, point.y.isFinite else { return }
    if let last = samples.last {
      guard time > last.time else { return }
      if hypot(point.x - last.point.x, point.y - last.point.y) > 0.5 { lastMovement = time }
    }
    samples.append(Sample(point: point, time: time))
    samples.removeAll { time - $0.time > 0.12 }
  }

  func released(at time: TimeInterval) -> NSPoint {
    guard let lastMovement, time - lastMovement <= 0.09,
      let first = samples.first, let last = samples.last, last.time - first.time >= 0.016
    else { return .zero }
    // Weighted regression smooths device jitter while favouring the final direction.
    let weights = samples.map { max(0.1, 1 - (last.time - $0.time) / 0.14) }
    let total = weights.reduce(0, +)
    let meanTime = zip(samples, weights).reduce(0) { $0 + ($1.0.time - last.time) * $1.1 } / total
    let meanX = zip(samples, weights).reduce(CGFloat(0)) { $0 + $1.0.point.x * $1.1 } / total
    let meanY = zip(samples, weights).reduce(CGFloat(0)) { $0 + $1.0.point.y * $1.1 } / total
    var denominator = 0.0
    var vx = 0.0
    var vy = 0.0
    for (sample, weight) in zip(samples, weights) {
      let dt = sample.time - last.time - meanTime
      denominator += weight * dt * dt
      vx += weight * dt * (sample.point.x - meanX)
      vy += weight * dt * (sample.point.y - meanY)
    }
    guard denominator > 0.000001 else { return .zero }
    vx /= denominator
    vy /= denominator
    let speed = hypot(vx, vy)
    guard speed >= 170 else { return .zero }
    let scale = min(1, 2400 / speed)
    return NSPoint(x: vx * scale, y: vy * scale)
  }
}

/// Analytic viscous drag: v(t) = v0 exp(-kt). Each axis can increase resistance
/// near an edge while keeping the release velocity continuous.
struct PaperGlide {
  static let resistance: CGFloat = 6
  let start: NSPoint
  let target: NSPoint
  private let x: Axis
  private let y: Axis
  var duration: TimeInterval { max(x.duration, y.duration) }

  init(start: NSPoint, velocity: NSPoint, size: NSSize, screens: [NSRect]) {
    self.start = start
    let natural = NSPoint(
      x: start.x + velocity.x / Self.resistance,
      y: start.y + velocity.y / Self.resistance)
    let candidates = screens.map { Self.containedOrigin(natural, size: size, screens: [$0]) }
    let startsOnScreen = screens.contains { $0.contains(NSRect(origin: start, size: size)) }
    let reachable =
      startsOnScreen
      ? candidates.filter {
        $0.x >= min(start.x, natural.x) - 0.01 && $0.x <= max(start.x, natural.x) + 0.01
          && $0.y >= min(start.y, natural.y) - 0.01 && $0.y <= max(start.y, natural.y) + 0.01
      } : []
    // Do not add momentum merely to reach the next display across a seam.
    target =
      (reachable.isEmpty ? candidates : reachable).min {
        hypot($0.x - natural.x, $0.y - natural.y) < hypot($1.x - natural.x, $1.y - natural.y)
      } ?? natural
    x = Axis(start: start.x, target: target.x, velocity: velocity.x)
    y = Axis(start: start.y, target: target.y, velocity: velocity.y)
  }

  func position(at time: TimeInterval) -> NSPoint {
    NSPoint(x: x.position(at: time), y: y.position(at: time))
  }

  /// Select a landing area across all displays, including vertically arranged
  /// displays and negative origins; never clamp to the primary screen alone.
  static func containedOrigin(_ point: NSPoint, size: NSSize, screens: [NSRect]) -> NSPoint {
    screens.map { screen in
      NSPoint(
        x: min(max(point.x, screen.minX), max(screen.minX, screen.maxX - size.width)),
        y: min(max(point.y, screen.minY), max(screen.minY, screen.maxY - size.height)))
    }.min {
      hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
    } ?? point
  }

  private struct Axis {
    let start: CGFloat
    let target: CGFloat
    let rate: CGFloat
    let returning: Bool
    let duration: TimeInterval

    init(start: CGFloat, target: CGFloat, velocity: CGFloat) {
      self.start = start
      self.target = target
      let distance = target - start
      returning =
        distance * velocity <= 0 || abs(distance) > abs(velocity) / PaperGlide.resistance + 0.01
      rate = returning ? 12 : max(PaperGlide.resistance, abs(velocity / distance))
      if abs(distance) < 0.05 {
        duration = 0
      } else if returning {
        duration = 0.75
      } else {
        duration = max(0, log(max(1, abs(distance) * rate / 2)) / rate)
      }
    }
    func position(at time: TimeInterval) -> CGFloat {
      guard duration > 0, time < duration else { return target }
      let t = CGFloat(max(0, time))
      let decay = exp(-rate * t)
      // A released note already outside a display settles back without overshoot.
      let remaining = returning ? (1 + rate * t) * decay : decay
      return target + (start - target) * remaining
    }
  }
}

/// One controller per panel. Tracks the real drag and coasts the actual window;
/// it never replaces the editor, changes its level, or persists intermediate frames.
final class PaperMovement {
  weak var window: NSWindow?
  var onSettled: ((NSPoint) -> Void)?
  private(set) var isDragging = false
  private(set) var isGliding = false
  var isActive: Bool { isDragging || isGliding }
  private var startPointer = NSPoint.zero
  private var startOrigin = NSPoint.zero
  private var velocity = ThrowVelocity()
  private var timer: Timer?
  private var trajectory: PaperGlide?
  private var started: TimeInterval = 0
  var screenFrames: () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) }
  var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  init(window: NSWindow) { self.window = window }
  deinit { timer?.invalidate() }

  func begin(at point: NSPoint, time: TimeInterval) {
    stop()
    guard let window else { return }
    isDragging = true
    startPointer = point
    startOrigin = window.frame.origin
    velocity = ThrowVelocity()
    velocity.add(point, at: time)
  }
  func drag(to point: NSPoint, time: TimeInterval) {
    guard isDragging, let window else { return }
    velocity.add(point, at: time)
    window.setFrameOrigin(
      NSPoint(
        x: startOrigin.x + point.x - startPointer.x,
        y: startOrigin.y + point.y - startPointer.y))
  }
  func release(at point: NSPoint, time: TimeInterval) {
    guard isDragging, let window else { return }
    drag(to: point, time: time)
    let speed = reduceMotion() ? .zero : velocity.released(at: time)
    let glide = PaperGlide(
      start: window.frame.origin, velocity: speed,
      size: window.frame.size, screens: screenFrames())
    isDragging = false
    isGliding = true
    guard !reduceMotion(), glide.duration > 0 else {
      window.setFrameOrigin(glide.target)
      stop()
      return
    }
    trajectory = glide
    started = ProcessInfo.processInfo.systemUptime
    let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
  private func tick() {
    guard let window, window.isVisible, let trajectory else {
      stop()
      return
    }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    window.setFrameOrigin(trajectory.position(at: elapsed))
    if elapsed >= trajectory.duration { stop() }
  }
  func stop() {
    let wasActive = isActive
    timer?.invalidate()
    timer = nil
    trajectory = nil
    isDragging = false
    isGliding = false
    if wasActive, let window { onSettled?(window.frame.origin) }
  }
}
