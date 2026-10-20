import AppKit
import CoreText

@main struct RichTextTests {
  static func main() throws {
    _ = NSApplication.shared
    for path in try FileManager.default.contentsOfDirectory(atPath: CommandLine.arguments[1])
    where path.hasSuffix(".ttf") {
      CTFontManagerRegisterFontsForURL(
        URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(path) as CFURL,
        .process, nil)
    }
    var n = Note(summary: "中英文手写\nReview the next step")
    n.attachments = [try Store.shared.importImage(URL(fileURLWithPath: CommandLine.arguments[2]))]
    n.details = "前面的文字\n后面的文字"
    n = try Store.shared.create(n)
    let owner = AppController()
    let panel = StickyPanel(
      contentRect: NSRect(x: 0, y: 0, width: 280, height: 266), styleMask: [.borderless],
      backing: .buffered, defer: false)
    panel.contentView = PaperView(note: n, owner: owner)
    owner.panels[n.id] = panel
    let d = DetailController(note: n, isNew: false, owner: owner)
    owner.details[n.id] = d
    func images() -> Int {
      var count = 0
      d.textView.textStorage!.enumerateAttribute(
        .attachment, in: NSRange(location: 0, length: d.textView.textStorage!.length)
      ) { v, _, _ in if v != nil { count += 1 } }
      return count
    }
    precondition(images() == 1)
    d.textView.insertText("新增 English 文本", replacementRange: NSRange(location: 3, length: 0))
    precondition(images() == 1, "Editing removed image")
    d.textView.setSelectedRange(NSRange(location: 0, length: 3))
    d.textView.toggleStrike()
    let didSave = d.saveDraft()
    precondition(didSave)
    let saved = try Store.shared.note(n.id)
    precondition(saved.attachments.count == 1)
    let data = try Data(
      contentsOf: Store.shared.root.appendingPathComponent("details").appendingPathComponent(
        saved.richContent!))
    let loaded = try NSAttributedString(
      data: data, options: [.documentType: NSAttributedString.DocumentType.rtfd],
      documentAttributes: nil)
    var count = 0
    loaded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: loaded.length)) {
      v, _, _ in if v != nil { count += 1 }
    }
    precondition(count == 1, "Saved RTFD lost image")
    precondition((loaded.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == 1)
    print(
      "PASS: native mixed Chinese/English editing, typography and strike preserve images through save/reload"
    )
  }
}
