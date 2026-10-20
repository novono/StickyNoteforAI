import AppKit

@main struct InertiaTests {
  static func main() throws {
    func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.01) -> Bool {
      abs(a - b) < tolerance
    }
    func settle(_ seconds: Double) {
      let end = Date().addingTimeInterval(seconds)
      while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    func sampleSpeed(_ speed: CGFloat, interval: Double) -> NSPoint {
      var tracker = ThrowVelocity()
      for i in 0...Int(0.1 / interval) {
        let time = Double(i) * interval
        tracker.add(NSPoint(x: time * speed, y: time * speed / 2), at: time)
      }
      return tracker.released(at: 0.1)
    }
    let fast = sampleSpeed(900, interval: 0.01)
    let sparse = sampleSpeed(900, interval: 0.02)
    precondition(near(fast.x, 900) && near(fast.y, 450))
    precondition(near(sparse.x, fast.x) && near(sparse.y, fast.y))
    precondition(sampleSpeed(60, interval: 0.01) == .zero)
    let capped = sampleSpeed(20_000, interval: 0.01)
    precondition(near(hypot(capped.x, capped.y), 2400))
    var held = ThrowVelocity()
    held.add(.zero, at: 0)
    held.add(NSPoint(x: 80, y: 0), at: 0.05)
    held.add(NSPoint(x: 80, y: 0), at: 0.2)
    precondition(held.released(at: 0.2) == .zero)
    var reversed = ThrowVelocity()
    for i in 0...30 {
      let t = Double(i) * 0.01
      reversed.add(NSPoint(x: i <= 10 ? CGFloat(i * 10) : CGFloat(200 - i * 10), y: 0), at: t)
    }
    precondition(reversed.released(at: 0.3).x < -900)

    let size = NSSize(width: 280, height: 266)
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let start = NSPoint(x: 300, y: 300)
    let glide = PaperGlide(start: start, velocity: fast, size: size, screens: [screen])
    let slower = PaperGlide(
      start: start, velocity: NSPoint(x: 450, y: 225), size: size, screens: [screen])
    precondition(glide.target.x > slower.target.x)
    precondition(near((glide.position(at: 0.00001).x - start.x) / 0.00001, fast.x, tolerance: 0.1))
    var previous = start.x
    var previousStep = CGFloat.greatestFiniteMagnitude
    for i in 1...120 {
      let next = glide.position(at: Double(i) / 120).x
      let step = next - previous
      precondition(step >= -0.001 && step <= previousStep + 0.001)
      previous = next
      previousStep = step
    }
    precondition(glide.position(at: 3) == glide.target)
    let edge = PaperGlide(
      start: NSPoint(x: 1100, y: 600),
      velocity: NSPoint(x: 1900, y: 700), size: size, screens: [screen])
    for i in 0...120 {
      precondition(screen.contains(NSRect(origin: edge.position(at: Double(i) / 120), size: size)))
    }
    let second = NSRect(x: 1440, y: 0, width: 1440, height: 900)
    let across = PaperGlide(
      start: NSPoint(x: 1150, y: 300),
      velocity: NSPoint(x: 2400, y: 0), size: size, screens: [screen, second])
    precondition(second.contains(NSRect(origin: across.target, size: size)))
    let seam = PaperGlide(
      start: NSPoint(x: 1150, y: 300),
      velocity: NSPoint(x: 900, y: 0), size: size, screens: [screen, second])
    precondition(seam.target.x <= 1300 && screen.contains(NSRect(origin: seam.target, size: size)))
    let upper = NSRect(x: -700, y: 900, width: 1440, height: 900)
    let vertical = PaperGlide(
      start: NSPoint(x: -500, y: 1300),
      velocity: NSPoint(x: -800, y: 600), size: size, screens: [screen, upper])
    precondition(upper.contains(NSRect(origin: vertical.target, size: size)))
    let outside = PaperGlide(
      start: NSPoint(x: -80, y: 200),
      velocity: .zero, size: size, screens: [screen])
    precondition(outside.target == NSPoint(x: 0, y: 200))
    precondition(outside.position(at: 0.2).x > -80 && outside.position(at: 0.2).x < 0)
    precondition(outside.position(at: 3) == outside.target)

    _ = NSApplication.shared
    let store = Store(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    let animator = ControlledWindowAnimator()
    let owner = AppController(store: store, windowAnimator: animator)
    var note = try store.create(Note(summary: "惯性回归测试"))
    owner.reload()
    let panel = owner.panels[note.id]!
    PaperMotion.finish(panel)
    let visible = NSScreen.screens.max(by: { $0.visibleFrame.width < $1.visibleFrame.width })!
      .visibleFrame
    let origin = NSPoint(x: visible.minX + 100, y: visible.minY + 100)
    panel.setFrameOrigin(origin)
    panel.orderFrontRegardless()
    panel.movement.screenFrames = { [visible] }
    panel.movement.reduceMotion = { false }
    var settlements = 0
    let persist = panel.movement.onSettled
    panel.movement.onSettled = { point in
      settlements += 1
      persist?(point)
    }
    func throwPanel() {
      let start = panel.frame.origin
      panel.movement.begin(at: start, time: 10)
      for i in 1...8 {
        panel.movement.drag(
          to: NSPoint(x: start.x + CGFloat(i * 8), y: start.y), time: 10 + Double(i) * 0.01)
      }
      panel.movement.release(at: NSPoint(x: start.x + 72, y: start.y), time: 10.09)
    }
    let baseline = try store.note(note.id)
    let editor = panel.contentView
    throwPanel()
    precondition(panel.movement.isGliding)
    let releasedAt = panel.frame.origin
    settle(0.1)
    precondition(panel.frame.minX > releasedAt.x && panel.contentView === editor)
    note = try store.note(note.id)
    precondition(note.x == baseline.x && note.y == baseline.y && settlements == 0)
    precondition(panel.level.rawValue == -1)
    settle(1.2)
    note = try store.note(note.id)
    precondition(!panel.movement.isActive && settlements == 1)
    precondition(near(note.x!, panel.frame.minX) && near(note.y!, panel.frame.minY))

    // Pressing anywhere on a moving paper immediately catches it.
    throwPanel()
    settle(0.06)
    let caught = panel.frame.origin
    let down = NSEvent.mouseEvent(
      with: .leftMouseDown, location: NSPoint(x: 120, y: 260),
      modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    panel.sendEvent(down)
    precondition(!panel.movement.isGliding)
    precondition(panel.movement.isDragging, "A paper-edge press must reach the drag controller")
    panel.movement.stop()
    settle(0.1)
    precondition(panel.frame.origin == caught)
    // Route real AppKit events through the surface, including changing local
    // coordinates as the window follows the pointer.
    let eventOrigin = panel.frame.origin
    let pointer = panel.convertPoint(toScreen: NSPoint(x: 120, y: 260))
    for i in 0...9 {
      let type: NSEvent.EventType =
        i == 0 ? .leftMouseDown : (i == 9 ? .leftMouseUp : .leftMouseDragged)
      let location = panel.convertPoint(
        fromScreen: NSPoint(x: pointer.x + CGFloat(i * 8), y: pointer.y))
      let event = NSEvent.mouseEvent(
        with: type, location: location,
        modifierFlags: [], timestamp: 30 + Double(i) * 0.01, windowNumber: panel.windowNumber,
        context: nil, eventNumber: i + 2, clickCount: 1, pressure: i == 9 ? 0 : 1)!
      panel.sendEvent(event)
    }
    precondition(near(panel.frame.minX, eventOrigin.x + 72))
    precondition(panel.movement.isGliding, "An AppKit edge drag must start coasting on release")
    panel.movement.stop()
    panel.movement.reduceMotion = { true }
    let beforeReduced = panel.frame.origin
    throwPanel()
    precondition(!panel.movement.isActive && near(panel.frame.minX, beforeReduced.x + 72))
    panel.movement.reduceMotion = { false }

    // Expanding cancels a coast; dragging the expanded paper updates its collapse anchor.
    throwPanel()
    owner.edit(note.id)
    precondition(!panel.movement.isActive)
    animator.finish()
    let detail = owner.details[note.id]!
    let oldAnchor = detail.collapsedFrame.origin
    let expandedOrigin = panel.frame.origin
    let dx: CGFloat = panel.frame.midX > visible.midX ? -40 : 40
    panel.movement.begin(at: expandedOrigin, time: 20)
    panel.movement.drag(to: NSPoint(x: expandedOrigin.x + dx, y: expandedOrigin.y), time: 20.5)
    panel.movement.release(at: NSPoint(x: expandedOrigin.x + dx, y: expandedOrigin.y), time: 20.6)
    settle(0.8)
    let expectedAnchor = PaperGlide.containedOrigin(
      NSPoint(
        x: oldAnchor.x + panel.frame.minX - expandedOrigin.x,
        y: oldAnchor.y + panel.frame.minY - expandedOrigin.y),
      size: size, screens: NSScreen.screens.map(\.visibleFrame))
    precondition(detail.collapsedFrame.origin == expectedAnchor)
    detail.collapse()
    animator.finish()
    precondition(panel.frame.origin == expectedAnchor && owner.panels[note.id] === panel)
    precondition(panel.level.rawValue == -1)
    note = try store.note(note.id)
    precondition(near(note.x!, expectedAnchor.x) && near(note.y!, expectedAnchor.y))

    throwPanel()
    owner.hideNotes()
    precondition(!panel.movement.isActive && !panel.isVisible)
    owner.showNotes()
    throwPanel()
    owner.mutate(note.id) { $0.completed = true }
    settle(0.8)
    precondition(!panel.movement.isActive && owner.panels[note.id] == nil && !panel.isVisible)
    print(
      "PASS: velocity sampling, slow/held release, speed cap, direction, exponential slowdown, multi-display edges, offscreen recovery, native window coast, no intermediate writes, grab interruption, reduced motion, desktop level, expanded anchor, hide/delete cleanup"
    )
  }
}
