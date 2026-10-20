import AppKit
import CoreText

@main struct RenderMotion {
  static func main() throws {
    _ = NSApplication.shared
    for path in try FileManager.default.contentsOfDirectory(atPath: CommandLine.arguments[1])
    where path.hasSuffix(".ttf") {
      CTFontManagerRegisterFontsForURL(
        URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(path) as CFURL,
        .process, nil)
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[2])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    func bitmap(_ size: NSSize) -> NSBitmapImageRep {
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    }
    let chosen = (0..<4).map { PaperAppearance(id: "sample-\($0)") }
    func paper(_ appearance: PaperAppearance) -> NSImage {
      let rep = bitmap(NSSize(width: 280, height: 266))
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      let surface = PaperSurface(frame: NSRect(x: 0, y: 0, width: 280, height: 266))
      surface.paperAppearance = appearance
      surface.draw(surface.bounds)
      let text = NSMutableAttributedString(string: "记下今天的想法\nMake a little space")
      applyPaperTypography(text, size: 22)
      text.draw(in: NSRect(x: 24, y: 136, width: 232, height: 96))
      NSGraphicsContext.restoreGraphicsState()
      let image = NSImage(size: rep.size)
      image.addRepresentation(rep)
      return image
    }
    // The same production renderer, sampled at meaningful moments.
    let sheet = bitmap(NSSize(width: 1600, height: 900))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1600, height: 900).fill()
    for (row, kind) in [PaperMotion.Kind.stick, .tear].enumerated() {
      for (col, time) in [0.0, 0.28, 0.55, 0.82].enumerated() {
        let view = PaperMotionView(
          frame: NSRect(x: 0, y: 0, width: 896, height: 882), image: paper(chosen[0]),
          color: paperColor("butter"), padding: 308, kind: kind, paperAppearance: chosen[0])
        view.progress = time
        let rep = bitmap(view.bounds.size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.draw(
          in: NSRect(x: CGFloat(col * 400), y: CGFloat((1 - row) * 450), width: 400, height: 391))
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    try sheet.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent("motion-contact.png"))
    let corners = bitmap(NSSize(width: 1200, height: 310))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: corners)
    NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 310).fill()
    for (i, a) in chosen.enumerated() {
      paper(a).draw(in: NSRect(x: CGFloat(i * 300) + 10, y: 22, width: 280, height: 266))
    }
    NSGraphicsContext.restoreGraphicsState()
    try corners.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent("paper-variation.png"))
    print("Rendered animation phases and four stable paper variations")
  }
}
