import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[1])
for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
where url.pathExtension == "ttf" {
  assert(CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil))
  print(url.lastPathComponent)
}
for name in [
  "PaperKai-Light", "PaperXing-Light", "PaperCao-Light", "PaperLatinKai-Light",
  "PaperLatinXing-Light", "PaperLatinCao-Light",
] {
  let f = NSFont(name: name, size: 22)!
  let ct = CTFontCreateWithName(f.fontName as CFString, 22, nil)
  var chars = Array(
    (!name.hasPrefix("PaperLatin") ? "确认交付时间开始新的计划中文手写" : "Review the next step").utf16)
  var glyphs = [CGGlyph](repeating: 0, count: chars.count)
  assert(CTFontGetGlyphsForCharacters(ct, &chars, &glyphs, chars.count))
  print("verified", f.fontName)
}
