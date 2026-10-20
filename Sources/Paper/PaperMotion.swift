import AppKit

/// A short-lived drawing surface inside the note's existing window. The actual
/// editor is retained, then restored unchanged after the paper settles.
final class PaperMotion {
  enum Kind { case stick, tear }
  private static var running: [ObjectIdentifier: PaperMotion] = [:]
  static func isAnimating(_ window: NSWindow) -> Bool { running[ObjectIdentifier(window)] != nil }
  static func finish(_ window: NSWindow) { running[ObjectIdentifier(window)]?.finish() }
  static func play(_ kind: Kind, on window: NSPanel, completion: (() -> Void)? = nil) {
    (window as? StickyPanel)?.movement.stop()
    finish(window)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      if kind == .stick {
        window.alphaValue = 1
        window.orderFrontRegardless()
      } else {
        window.close()
      }
      completion?()
      return
    }
    guard let content = window.contentView,
      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)
    else {
      if kind == .stick { window.orderFrontRegardless() } else { window.close() }
      completion?()
      return
    }
    content.cacheDisplay(in: content.bounds, to: bitmap)
    let image = NSImage(size: content.bounds.size)
    image.addRepresentation(bitmap)
    let motion = PaperMotion(
      kind: kind, window: window, original: content, image: image, completion: completion)
    running[ObjectIdentifier(window)] = motion
    motion.start()
  }
  let kind: Kind
  let window: NSPanel
  let original: NSView
  let originalFrame: NSRect
  let originalShadow: Bool
  let originalDelegate: NSWindowDelegate?
  let surface: PaperMotionView
  let completion: (() -> Void)?
  var timer: Timer?
  var started: TimeInterval = 0
  var finished = false
  var duration: TimeInterval {
    kind == .stick
      ? surface.paperAppearance.arrivalDuration : surface.paperAppearance.removalDuration
  }

  private init(
    kind: Kind, window: NSPanel, original: NSView, image: NSImage, completion: (() -> Void)?
  ) {
    self.kind = kind
    self.window = window
    self.original = original
    originalFrame = window.frame
    originalShadow = window.hasShadow
    originalDelegate = window.delegate
    self.completion = completion
    // The reflected back travels above the original sheet as it peels up.
    let padding = max(72, max(originalFrame.width, originalFrame.height) * 1.1)
    let color = (original as? PaperSurface)?.paperBaseColor ?? paperColor("butter")
    surface = PaperMotionView(
      frame: NSRect(origin: .zero, size: originalFrame.insetBy(dx: -padding, dy: -padding).size),
      image: image, color: color, padding: padding, kind: kind,
      paperAppearance: (original as? PaperSurface)?.paperAppearance
        ?? PaperAppearance(id: window.identifier?.rawValue ?? "paper"))
  }
  private func start() {
    // Suppress persistence of intermediate animation frames.
    window.delegate = nil
    window.hasShadow = false
    window.alphaValue = 1
    window.animationBehavior = .none
    window.contentView = surface
    window.setFrame(
      originalFrame.insetBy(dx: -surface.padding, dy: -surface.padding), display: false)
    surface.frame = NSRect(origin: .zero, size: window.frame.size)
    window.orderFrontRegardless()
    surface.displayIfNeeded()
    started = ProcessInfo.processInfo.systemUptime
    let tick = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      let progress = (ProcessInfo.processInfo.systemUptime - self.started) / self.duration
      self.surface.progress = min(1, progress)
      if progress >= 1 { self.finish() }
    }
    timer = tick
    RunLoop.main.add(tick, forMode: .common)
  }
  private func finish() {
    guard !finished else { return }
    finished = true
    timer?.invalidate()
    timer = nil
    window.delegate = nil
    window.setFrame(originalFrame, display: false)
    window.contentView = original
    original.frame = NSRect(origin: .zero, size: originalFrame.size)
    window.hasShadow = originalShadow
    window.alphaValue = 1
    if kind == .tear {
      window.orderOut(nil)
      window.close()
    } else {
      window.delegate = originalDelegate
      original.needsDisplay = true
      window.displayIfNeeded()
    }
    Self.running.removeValue(forKey: ObjectIdentifier(window))
    completion?()
  }
}

final class PaperMotionView: NSView {
  let image: NSImage
  let color: NSColor
  let padding: CGFloat
  let kind: PaperMotion.Kind
  let paperAppearance: PaperAppearance
  var progress: Double = 0 { didSet { needsDisplay = true } }
  init(
    frame: NSRect, image: NSImage, color: NSColor, padding: CGFloat, kind: PaperMotion.Kind,
    paperAppearance: PaperAppearance
  ) {
    self.image = image
    self.color = color
    self.padding = padding
    self.kind = kind
    self.paperAppearance = paperAppearance
    super.init(frame: frame)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isOpaque: Bool { false }
  override func mouseDown(with event: NSEvent) {}  // Consume clicks until the editor is restored.
  private func smooth(_ t: Double) -> CGFloat {
    let x = CGFloat(min(1, max(0, t)))
    return x * x * (3 - 2 * x)
  }
  private func path(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    if let first = points.first {
      path.move(to: first)
      for p in points.dropFirst() { path.line(to: p) }
      path.close()
    }
    return path
  }
  /// Clip a convex paper polygon against a moving diagonal fold.
  private func clip(_ points: [NSPoint], a: CGFloat, b: CGFloat, c: CGFloat, front: Bool)
    -> [NSPoint]
  {
    guard let last = points.last else { return [] }
    var result: [NSPoint] = []
    var previous = last
    func distance(_ p: NSPoint) -> CGFloat { (a * p.x + b * p.y - c) * (front ? 1 : -1) }
    for current in points {
      let d0 = distance(previous)
      let d1 = distance(current)
      if (d0 <= 0) != (d1 <= 0) {
        let t = d0 / (d0 - d1)
        result.append(
          NSPoint(
            x: previous.x + (current.x - previous.x) * t,
            y: previous.y + (current.y - previous.y) * t))
      }
      if d1 <= 0 { result.append(current) }
      previous = current
    }
    return result
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor.clear.setFill()
    bounds.fill(using: .copy)
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let w = image.size.width
    let h = image.size.height
    let t = progress
    let landing = smooth(t / 0.8)
    let peeling = smooth((t - 0.06) / 0.84)
    let departing = smooth((t - 0.57) / 0.43)
    let lift = kind == .stick ? 1 - landing : departing
    context.saveGState()
    context.translateBy(x: padding + w / 2, y: padding + h / 2)
    if kind == .stick {
      context.translateBy(x: -10 * lift, y: 34 * lift)
      context.rotate(by: paperAppearance.tilt * lift)
      context.scaleBy(x: 1 + 0.025 * lift, y: 1 - 0.09 * lift)
    } else {
      context.translateBy(x: -departing * w * 0.12, y: departing * h * 0.18)
      context.rotate(by: -paperAppearance.tilt * 1.8 * departing)
      context.scaleBy(x: 1 - 0.1 * departing, y: 1 - 0.1 * departing)
      context.setAlpha(1 - smooth((t - 0.80) / 0.20))
    }
    context.translateBy(x: -w / 2, y: -h / 2)
    let corners = [
      NSPoint(x: 0, y: 0), NSPoint(x: w, y: 0), NSPoint(x: w, y: h), NSPoint(x: 0, y: h),
    ]
    let curl = kind == .stick ? min(w, h) * 0.55 * (1 - smooth(t / 0.92)) : (w + h) * 0.94 * peeling
    let (a, b, c) = paperAppearance.foldLine(size: image.size, amount: curl)
    let front = clip(corners, a: a, b: b, c: c, front: true)
    let lifted = clip(corners, a: a, b: b, c: c, front: false)
    let back = lifted.map { p -> NSPoint in
      let d = (a * p.x + b * p.y - c) / (a * a + b * b)
      return NSPoint(x: p.x - 2 * a * d, y: p.y - 2 * b * d)
    }
    let face = path(front)
    let fold = path(back)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(paperAppearance.shadowOpacity)
    shadow.shadowBlurRadius = 6 + 16 * lift
    shadow.shadowOffset = NSSize(width: 2 + 5 * lift, height: -3 - 9 * lift)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color.setFill()
    face.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    face.addClip()
    image.draw(
      in: NSRect(origin: .zero, size: image.size), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    if back.count >= 3 && fold.bounds.width > 0.5 && fold.bounds.height > 0.5 {
      let creaseShadow = NSShadow()
      creaseShadow.shadowColor = NSColor.black.withAlphaComponent(
        paperAppearance.shadowOpacity + 0.06)
      creaseShadow.shadowBlurRadius = paperAppearance.shadowBlur + 4
      creaseShadow.shadowOffset = NSSize(width: kind == .stick ? -3 : 3, height: -4)
      NSGraphicsContext.saveGraphicsState()
      creaseShadow.set()
      color.setFill()
      fold.fill()
      NSGraphicsContext.restoreGraphicsState()
      NSGradient(colors: [
        color.blended(withFraction: paperAppearance.backLightness, of: .white)!,
        color.blended(withFraction: 0.06, of: .white)!,
        color.blended(withFraction: paperAppearance.creaseStrength, of: .black)!,
      ])?.draw(in: fold, angle: kind == .stick ? 135 : 45)
      NSGraphicsContext.saveGraphicsState()
      fold.addClip()
      PaperTexture.draw(in: fold.bounds, appearance: paperAppearance, strength: 0.65)
      NSGraphicsContext.restoreGraphicsState()
      color.blended(withFraction: 0.25, of: .white)!.setStroke()
      fold.lineWidth = 0.65
      fold.stroke()
    }
    context.restoreGState()
  }
}
