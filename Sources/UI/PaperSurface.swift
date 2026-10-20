import AppKit
import QuartzCore

func paperLockButton(target: AnyObject, action: Selector) -> NSButton {
  let button = NSButton()
  button.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "解除置顶锁定")
  button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
  button.imagePosition = .imageOnly
  button.isBordered = false
  button.contentTintColor = ink.withAlphaComponent(0.45)
  button.autoresizingMask = [.minXMargin, .minYMargin]
  button.identifier = NSUserInterfaceItemIdentifier("paper-unlock")
  button.toolTip = "解除锁定，放回桌面"
  button.setAccessibilityLabel("解除置顶锁定")
  button.target = target
  button.action = action
  return button
}

class PaperSurface: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    layer?.contentsScale = window?.backingScaleFactor ?? 2
  }
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    layer?.contentsScale = window?.backingScaleFactor ?? 2
  }
  var paperAppearance = PaperAppearance(id: "paper") { didSet { needsDisplay = true } }
  var paperCreatedAt = Date().timeIntervalSince1970 {
    didSet { refreshPaperAge() }
  }
  private(set) var paperAge = PaperAge.fresh
  var paperBaseColor: NSColor { paperAge.tint(paperColor(colorKey)) }
  func refreshPaperAge(now: TimeInterval = Date().timeIntervalSince1970) {
    let age = PaperAge(createdAt: paperCreatedAt, now: now)
    if age != paperAge {
      paperAge = age
      needsDisplay = true
    }
  }
  var onDoubleClick: (() -> Void)?
  var allowsDragging = true
  var contextActions: (() -> NSMenu)?
  override func menu(for event: NSEvent) -> NSMenu? { contextActions?() ?? super.menu(for: event) }
  var colorKey = "butter" { didSet { needsDisplay = true } }
  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let w = bounds.width
    let h = bounds.height
    let fw = paperAppearance.curlWidth
    let fh = paperAppearance.curlHeight
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
      paperAppearance.cornerPoint(NSPoint(x: x, y: y), size: bounds.size)
    }
    let paper = NSBezierPath()
    paper.move(to: point(0, 0))
    paper.line(to: point(w - fw, 0))
    paper.line(to: point(w, fh))
    paper.line(to: point(w, h))
    paper.line(to: point(0, h))
    paper.close()
    paper.addClip()
    let base = paperBaseColor
    NSGradient(starting: base.blended(withFraction: 0.10, of: .white)!, ending: base)?.draw(
      in: bounds, angle: -90)
    PaperTexture.draw(in: bounds, appearance: paperAppearance)
    paperAge.drawEdges(in: bounds, appearance: paperAppearance)
    NSColor.black.withAlphaComponent(0.025).setStroke()
    let edge = NSBezierPath()
    edge.move(to: point(0, 1))
    edge.curve(
      to: point(w - fw, 1), controlPoint1: point(w * 0.3, 4), controlPoint2: point(w * 0.72, 0))
    edge.lineWidth = 1
    edge.stroke()
    let fold = NSBezierPath()
    fold.move(to: point(w - fw, 0))
    fold.curve(
      to: point(w, fh), controlPoint1: point(w - fw * 0.45, fh * 0.12),
      controlPoint2: point(w - fw * 0.04, fh * 0.68))
    fold.curve(
      to: point(w - fw * 0.94, fh * 1.09), controlPoint1: point(w - fw * 0.35, fh * 0.95),
      controlPoint2: point(w - fw * 0.75, fh * 1.18))
    fold.curve(
      to: point(w - fw, 0), controlPoint1: point(w - fw * 1.07, fh * 0.75),
      controlPoint2: point(w - fw * 1.03, fh * 0.28))
    fold.close()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(paperAppearance.shadowOpacity)
    shadow.shadowBlurRadius = paperAppearance.shadowBlur
    shadow.shadowOffset = NSSize(
      width: paperAppearance.onLeft ? 1.5 : -1.5, height: paperAppearance.onTop ? -1.5 : 1.5)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    base.setFill()
    fold.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
      base.blended(withFraction: paperAppearance.backLightness, of: .white)!,
      base.blended(withFraction: paperAppearance.creaseStrength, of: .black)!,
    ])?.draw(in: fold, angle: paperAppearance.onLeft ? 45 : 135)
    NSGraphicsContext.saveGraphicsState()
    fold.addClip()
    PaperTexture.draw(in: fold.bounds, appearance: paperAppearance, strength: 0.65)
    NSGraphicsContext.restoreGraphicsState()
    base.blended(withFraction: 0.25, of: .white)!.withAlphaComponent(0.7).setStroke()
    fold.lineWidth = 0.45
    fold.stroke()
  }
  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2, let action = onDoubleClick {
      action()
    } else if allowsDragging {
      (window as? StickyPanel)?.movement.begin(at: screenPoint(for: event), time: event.timestamp)
    }
  }
  override func mouseDragged(with event: NSEvent) {
    (window as? StickyPanel)?.movement.drag(to: screenPoint(for: event), time: event.timestamp)
  }
  override func mouseUp(with event: NSEvent) {
    (window as? StickyPanel)?.movement.release(at: screenPoint(for: event), time: event.timestamp)
  }
  private func screenPoint(for event: NSEvent) -> NSPoint {
    // Position and timestamp must come from the same event, even when AppKit
    // delivers queued events after the physical pointer has already moved.
    window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
  }
}
