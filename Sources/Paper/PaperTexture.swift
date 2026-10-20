import AppKit

/// A transparent, color-independent paper stock texture, cached at Retina
/// resolution. A note's seed stays fixed so repainting never makes it shimmer.
enum PaperTexture {
  private static let cache: NSCache<NSNumber, NSImage> = {
    let cache = NSCache<NSNumber, NSImage>()
    cache.countLimit = 24
    return cache
  }()

  static func draw(in rect: NSRect, appearance: PaperAppearance, strength: CGFloat = 1) {
    let key = NSNumber(value: appearance.grainOffset)
    let image: NSImage
    if let existing = cache.object(forKey: key) {
      image = existing
    } else {
      image = make(seed: appearance.grainOffset)
      cache.setObject(image, forKey: key)
    }
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext.current?.cgContext
    // Composite as a group to preserve the whole sheet's departing opacity.
    if strength != 1 {
      context?.beginTransparencyLayer(auxiliaryInfo: nil)
      context?.setAlpha(strength)
    }
    NSColor(patternImage: image).setFill()
    rect.fill()
    if strength != 1 { context?.endTransparencyLayer() }
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func make(seed: Int) -> NSImage {
    let side = 512
    let points: CGFloat = 256
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bitmapFormat: .alphaNonpremultiplied, bytesPerRow: side * 4,
      bitsPerPixel: 32)!
    var state = UInt64(seed) &+ 0x9e37_79b9_7f4a_7c15
    func next() -> Double {
      state ^= state >> 12
      state ^= state << 25
      state ^= state >> 27
      return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(UInt64(1) << 53)
    }
    let phase = next() * Double.pi * 2
    let wave = (0..<side).map { Double($0) / Double(side) * Double.pi * 2 }
    let horizontal = wave.map { cos($0 * 2 + phase) * 0.0015 + sin($0 * 7 - phase) * 0.0008 }
    let vertical = wave.map { sin($0 * 3 + phase) * 0.0015 + cos($0 * 5 + phase) * 0.0008 }
    let bytes = bitmap.bitmapData!
    for y in 0..<side {
      for x in 0..<side {
        // Fine, low-contrast pulp replaces the former pepper-like black noise.
        let density = (next() + next() + next() + next() - 2) * 0.012 + horizontal[x] + vertical[y]
        let i = (y * side + x) * 4
        let value: UInt8 = density > 0 ? 255 : 0
        bytes[i] = value
        bytes[i + 1] = value
        bytes[i + 2] = value
        bytes[i + 3] = UInt8(min(255, abs(density) * 255))
      }
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    if let context = NSGraphicsContext.current?.cgContext {
      context.scaleBy(x: 2, y: 2)
      context.setLineCap(.round)
      // Short, irregular fibres have a soft light edge and a faint recess.
      for _ in 0..<180 {
        let x = CGFloat(next()) * points
        let y = CGFloat(next()) * points
        let length = CGFloat(1.6 + next() * 4.8)
        let angle = next() * Double.pi
        let dx = CGFloat(cos(angle)) * length
        let dy = CGFloat(sin(angle)) * length
        let bend = CGFloat(next() - 0.5) * 1.2
        for light in [false, true] {
          let offset: CGFloat = light ? 0.35 : 0
          context.setStrokeColor(CGColor(gray: light ? 1 : 0, alpha: light ? 0.065 : 0.014))
          context.setLineWidth(light ? 0.28 : 0.30)
          context.move(to: CGPoint(x: x, y: y + offset))
          context.addQuadCurve(
            to: CGPoint(x: x + dx, y: y + dy + offset),
            control: CGPoint(x: x + dx * 0.5 + bend, y: y + dy * 0.5 - bend + offset))
          context.strokePath()
        }
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: points, height: points)
    let image = NSImage(size: bitmap.size)
    image.addRepresentation(bitmap)
    return image
  }
}
