import AppKit

/// Time changes the paper stock, never its ink or document. The first six hours
/// stay fresh; wear eases toward a fixed ceiling at thirty days.
struct PaperAge: Equatable {
  let amount: CGFloat
  static let fresh = PaperAge(createdAt: 0, now: 0)

  init(createdAt: TimeInterval, now: TimeInterval = Date().timeIntervalSince1970) {
    guard createdAt.isFinite, now.isFinite else {
      amount = 0
      return
    }
    let days = max(0, now - createdAt) / 86_400
    let progress = min(1, max(0, (days - 0.25) / 29.75))
    amount = CGFloat((1 - exp(-3 * progress)) / (1 - exp(-3)))
  }

  func tint(_ color: NSColor) -> NSColor {
    let warmth = NSColor(calibratedRed: 0.70, green: 0.58, blue: 0.36, alpha: 1)
    return color.blended(withFraction: amount * 0.018, of: warmth) ?? color
  }

  func drawEdges(in rect: NSRect, appearance: PaperAppearance) {
    guard amount > 0, rect.width > 0, rect.height > 0 else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    // All wear is outside the editor's 24/28-point text inset, at either size.
    let band = min(CGFloat(17), min(rect.width, rect.height) * 0.065)
    let margin = NSBezierPath(rect: rect)
    margin.append(NSBezierPath(rect: rect.insetBy(dx: band, dy: band)))
    margin.windingRule = .evenOdd
    margin.addClip()
    let tone = NSColor(calibratedRed: 0.47, green: 0.37, blue: 0.22, alpha: 1)
    let fade = NSGradient(
      starting: tone.withAlphaComponent(amount * 0.065),
      ending: tone.withAlphaComponent(0))!
    fade.draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: band), angle: 90)
    fade.draw(
      in: NSRect(x: rect.minX, y: rect.maxY - band, width: rect.width, height: band), angle: -90)
    fade.draw(in: NSRect(x: rect.minX, y: rect.minY, width: band, height: rect.height), angle: 0)
    fade.draw(
      in: NSRect(x: rect.maxX - band, y: rect.minY, width: band, height: rect.height), angle: 180)

    // Fixed, broad contact marks build up at the edge rather than adding dark
    // speckles beneath the writing. The same sheet keeps the same marks.
    var seed = UInt64(appearance.grainOffset) &+ 0x517c_c1b7_2722_0a95
    func next() -> CGFloat {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return CGFloat(seed >> 11) / CGFloat(UInt64(1) << 53)
    }
    for index in 0..<16 {
      let along = 0.04 + next() * 0.92
      let length = 18 + next() * 44
      let depth = 5 + next() * 8
      let opacity = amount * (0.022 + next() * 0.022)
      let horizontal = index % 4 < 2
      let x = horizontal ? rect.minX + rect.width * along : (index % 4 == 2 ? rect.minX : rect.maxX)
      let y =
        horizontal ? (index % 4 == 0 ? rect.minY : rect.maxY) : rect.minY + rect.height * along
      let mark = NSRect(
        x: x - (horizontal ? length : depth) / 2,
        y: y - (horizontal ? depth : length) / 2,
        width: horizontal ? length : depth, height: horizontal ? depth : length)
      NSGradient(starting: tone.withAlphaComponent(opacity), ending: tone.withAlphaComponent(0))?
        .draw(in: NSBezierPath(ovalIn: mark), relativeCenterPosition: .zero)
    }
  }
}
