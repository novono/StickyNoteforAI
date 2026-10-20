import AppKit
import Foundation

let target = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
for n in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let px = n * scale
    let image = NSImage(size: NSSize(width: px, height: px))
    image.lockFocus()
    let tx = NSAffineTransform()
    tx.scale(by: CGFloat(px) / 1024)
    tx.concat()
    NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.85, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210
    ).fill()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
    shadow.shadowBlurRadius = 32
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    NSColor(calibratedRed: 0.98, green: 0.89, blue: 0.52, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 190, y: 182, width: 644, height: 680), xRadius: 8, yRadius: 8
    ).fill()
    NSShadow().set()
    NSColor(calibratedRed: 0.92, green: 0.81, blue: 0.40, alpha: 0.5).setFill()
    NSRect(x: 190, y: 760, width: 644, height: 102).fill()
    NSColor(calibratedRed: 0.30, green: 0.29, blue: 0.20, alpha: 0.8).setStroke()
    for (y, width) in [(610, 410), (488, 354), (366, 232)] {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: 290, y: y))
      line.line(to: NSPoint(x: 290 + width, y: y))
      line.lineWidth = 24
      line.lineCapStyle = .round
      line.stroke()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: target).appendingPathComponent(
        "icon_\(n)x\(n)\(scale == 2 ? "@2x" : "").png"))
  }
}
