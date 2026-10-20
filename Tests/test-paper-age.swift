import AppKit
import CoreText

@main struct PaperAgeTests {
  static func main() throws {
    _ = NSApplication.shared
    let resources = URL(fileURLWithPath: CommandLine.arguments[1])
    let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for url in try FileManager.default.contentsOfDirectory(
      at: resources, includingPropertiesForKeys: nil)
    where url.pathExtension == "ttf" {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    let day: Double = 86_400
    precondition(PaperAge(createdAt: 0, now: day / 4).amount == 0)
    precondition(PaperAge(createdAt: day, now: 0).amount == 0)
    precondition(PaperAge(createdAt: .nan, now: day).amount == 0)
    let ages = (0...300).map { PaperAge(createdAt: 0, now: Double($0) * day / 10).amount }
    precondition(zip(ages, ages.dropFirst()).allSatisfy { $0.0 <= $0.1 })
    precondition(ages.last == 1 && PaperAge(createdAt: 0, now: 365 * day).amount == 1)

    func bitmap(_ size: NSSize, scale: Int = 1) -> NSBitmapImageRep {
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
        pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
      rep.size = size
      return rep
    }
    func render(_ days: Double, color: String, text: Bool = false, scale: Int = 1)
      -> NSBitmapImageRep
    {
      let rep = bitmap(NSSize(width: 280, height: 266), scale: scale)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
      let surface = PaperSurface(frame: NSRect(x: 0, y: 0, width: 280, height: 266))
      surface.paperAppearance = PaperAppearance(id: "clean-stock-\(color)")
      surface.colorKey = color
      surface.paperCreatedAt = 0
      surface.refreshPaperAge(now: days * day)
      surface.draw(surface.bounds)
      if text {
        let content = NSMutableAttributedString(string: "记下今天的想法\nMake a little space\n\n留一点时间，慢慢来")
        applyPaperTypography(content, size: 22)
        content.draw(in: NSRect(x: 24, y: 24, width: 232, height: 210))
      }
      NSGraphicsContext.restoreGraphicsState()
      return rep
    }
    func components(_ color: NSColor) -> [CGFloat] {
      let rgb = color.usingColorSpace(.sRGB)!
      return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
    }
    func luminance(_ rgb: [CGFloat]) -> CGFloat {
      let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
      return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
    }
    let inkLuminance = luminance(components(ink))
    var lowestContrast: CGFloat = .greatestFiniteMagnitude
    var minimumContrastRetention: CGFloat = 1
    var maximumCenterChange: CGFloat = 0
    for (key, _, _) in paperColors {
      let fresh = render(0, color: key)
      let oldest = render(365, color: key)
      precondition(
        fresh.representation(using: .png, properties: [:])
          == render(0, color: key).representation(using: .png, properties: [:]))
      for y in stride(from: 26, to: 240, by: 3) {
        for x in stride(from: 26, to: 254, by: 3) {
          let clean = components(fresh.colorAt(x: x, y: y)!)
          let aged = components(oldest.colorAt(x: x, y: y)!)
          maximumCenterChange = max(
            maximumCenterChange, zip(clean, aged).map { abs($0.0 - $0.1) }.max()!)
          let contrast = (luminance(aged) + 0.05) / (inkLuminance + 0.05)
          let freshContrast = (luminance(clean) + 0.05) / (inkLuminance + 0.05)
          lowestContrast = min(lowestContrast, contrast)
          minimumContrastRetention = min(minimumContrastRetention, contrast / freshContrast)
        }
      }
    }
    precondition(maximumCenterChange < 0.025, "Patina must not intrude into the reading area")
    precondition(
      lowestContrast > 6 && minimumContrastRetention > 0.97,
      "Aging must preserve the palette's ink contrast: \(lowestContrast), \(minimumContrastRetention)"
    )

    // Idle paper ages without touching the document, metadata or revision.
    let store = Store(root: output.appendingPathComponent("store"))
    var note = Note(summary: "时间只改变纸面")
    let now = Date().timeIntervalSince1970
    note.createdAt = now - 3 * day
    note = try store.create(note)
    let owner = AppController(store: store)
    owner.reload()
    let panel = owner.panels[note.id]!
    PaperMotion.finish(panel)
    let front = panel.contentView as! PaperView
    let ageBefore = front.paperAge.amount
    let bytesBefore = try Data(contentsOf: store.root.appendingPathComponent("notes.json"))
    owner.refreshPaperAges(now: now + 10 * day)
    precondition(front.paperAge.amount > ageBefore)
    let bytesAfter = try Data(contentsOf: store.root.appendingPathComponent("notes.json"))
    precondition(bytesAfter == bytesBefore)
    _ = try NoteDocuments(store: store).saveSummary(
      base: note, text: NSAttributedString(string: "编辑后纸龄保留"))
    owner.reload()
    precondition(front.paperCreatedAt == note.createdAt)
    let detail = DetailController(note: try store.note(note.id), isNew: false, owner: owner)
    let expanded = detail.window!.contentView as! PaperSurface
    precondition(expanded.paperCreatedAt == note.createdAt)
    panel.close()

    // Contact sheet uses production drawing at fixed simulated ages.
    let sheet = bitmap(NSSize(width: 1200, height: 1230))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: sheet.size).fill()
    for (column, entry) in [(0.0, "刚贴上"), (3.0, "3 天"), (10.0, "10 天"), (30.0, "30 天 · 老化上限")]
      .enumerated()
    {
      (entry.1 as NSString).draw(
        at: NSPoint(x: CGFloat(column * 300 + 18), y: 1196),
        withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.darkGray])
      for (row, color) in paperColors.enumerated() {
        let rep = render(entry.0, color: color.0, text: true, scale: 2)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.draw(
          in: NSRect(
            x: CGFloat(column * 300 + 10), y: CGFloat(900 - row * 296), width: 280, height: 266))
      }
    }
    NSGraphicsContext.restoreGraphicsState()
    try sheet.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent("paper-aging.png"))
    try render(0, color: "butter", text: true, scale: 2).representation(
      using: .png, properties: [:])!
      .write(to: output.appendingPathComponent("fresh-paper.png"))
    print(
      "PASS: fresh grace period, monotonic bounded aging, future/invalid clocks, deterministic stock, protected reading area, contrast \(lowestContrast), minute refresh without writes, edit/detail age continuity"
    )
  }
}
