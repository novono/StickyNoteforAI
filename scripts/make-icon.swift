import AppKit
import Foundation

// Export the approved artwork without changing its shape, color or alpha.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.png build/AppIcon.iconset
guard CommandLine.arguments.count == 3 else {
  fputs("Usage: make-icon.swift <source.png> <output.iconset>\n", stderr)
  exit(1)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let target = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let source = NSImage(contentsOf: sourceURL),
  let sourceBitmap = NSBitmapImageRep(data: try Data(contentsOf: sourceURL)),
  sourceBitmap.pixelsWide == sourceBitmap.pixelsHigh, sourceBitmap.pixelsWide >= 1024,
  sourceBitmap.hasAlpha
else {
  fputs("Expected a square PNG with transparency, at least 1024 pixels wide.\n", stderr)
  exit(1)
}
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
for n in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = n * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
      in: NSRect(x: 0, y: 0, width: px, height: px),
      from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: target.appendingPathComponent(
        "icon_\(n)x\(n)\(scale == 2 ? "@2x" : "").png"))
  }
}
print("Exported 10 icon representations to \(target.path)")
