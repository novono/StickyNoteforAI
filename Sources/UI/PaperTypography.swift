import AppKit
import CoreText

func registerPaperFont() {
  for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
  }
}
let paperScripts = [("kai", "楷书"), ("xing", "行书"), ("cao", "草书")]
func paperFont(_ size: CGFloat, script: String = "xing", latin: Bool = false) -> NSFont {
  let pair: [String] =
    script == "kai"
    ? ["PaperKai-Light", "PaperLatinKai-Light"]
    : script == "cao"
      ? ["PaperCao-Light", "PaperLatinCao-Light"] : ["PaperXing-Light", "PaperLatinXing-Light"]
  let adjusted = latin ? size * (script == "cao" ? 1.30 : script == "xing" ? 1.15 : 1.0) : size
  return NSFont(name: pair[latin ? 1 : 0], size: adjusted) ?? NSFont(
    name: "LXGWWenKai-Regular", size: size) ?? NSFont(name: "Kaiti SC", size: size)
    ?? .systemFont(ofSize: size)
}
func applyPaperTypography(_ text: NSMutableAttributedString, size: CGFloat, script: String = "xing")
{
  let range = NSRange(location: 0, length: text.length)
  text.addAttributes(summaryStyle(size, script: script), range: range)
  let latin = try! NSRegularExpression(pattern: "[\\u0000-\\u024F]+")
  for match in latin.matches(in: text.string, range: range) {
    text.addAttribute(
      .font, value: paperFont(size, script: script, latin: true), range: match.range)
  }
}

let ink = NSColor(calibratedRed: 0.24, green: 0.23, blue: 0.18, alpha: 1)
let paperColors: [(String, String, NSColor)] = [
  ("butter", "奶油黄", NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.61, alpha: 1)),
  ("rose", "桃子粉", NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.79, alpha: 1)),
  ("sage", "鼠尾草绿", NSColor(calibratedRed: 0.83, green: 0.89, blue: 0.72, alpha: 1)),
  ("blue", "天空蓝", NSColor(calibratedRed: 0.79, green: 0.88, blue: 0.94, alpha: 1)),
]
func paperColor(_ key: String) -> NSColor {
  paperColors.first { $0.0 == key }?.2 ?? paperColors[0].2
}
func summaryStyle(_ size: CGFloat, script: String = "xing") -> [NSAttributedString.Key: Any] {
  let p = NSMutableParagraphStyle()
  p.lineSpacing = 3
  p.lineBreakMode = .byWordWrapping
  return [.font: paperFont(size, script: script), .foregroundColor: ink, .paragraphStyle: p]
}
func summaryHeight(_ text: String, size: CGFloat, script: String = "xing") -> CGFloat {
  let rich = NSMutableAttributedString(string: text)
  applyPaperTypography(rich, size: size, script: script)
  return rich.boundingRect(
    with: NSSize(width: 232, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading]
  ).height
}
