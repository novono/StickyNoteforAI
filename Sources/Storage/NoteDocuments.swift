import AppKit
import CryptoKit

/// Rich documents and draft conflict checks are shared by the editors and AI
/// commands. Window controllers only handle interaction and presentation.
struct NoteDocuments {
  let store: Store

  func detail(_ note: Note) -> NSMutableAttributedString {
    if let name = note.richContent,
      let bytes = try? Data(
        contentsOf: store.root.appendingPathComponent("details").appendingPathComponent(name)),
      let rich = try? NSAttributedString(
        data: bytes, options: [.documentType: NSAttributedString.DocumentType.rtfd],
        documentAttributes: nil)
    {
      return NSMutableAttributedString(attributedString: rich)
    }
    let text = NSMutableAttributedString(
      string: note.details,
      attributes: summaryStyle(note.fontSize ?? 22, script: note.fontStyle ?? "xing"))
    for attachment in note.attachments { append(attachment, to: text) }
    return text
  }

  func append(_ attachment: Attachment, to text: NSMutableAttributedString) {
    guard let wrapper = try? FileWrapper(url: store.attachmentURL(attachment), options: .immediate)
    else { return }
    text.append(NSAttributedString(string: "\n"))
    text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
    text.append(NSAttributedString(string: "\n"))
  }

  func write(_ text: NSAttributedString) throws -> String {
    try store.prepare()
    let data = try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
    let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".rtfd"
    let url = store.root.appendingPathComponent("details").appendingPathComponent(name)
    // Immutable documents are safe for concurrent readers, and identical
    // autosaves reuse the same file rather than growing the store.
    if !store.fm.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
    return name
  }

  func saveSummary(base: Note, text: NSAttributedString) throws -> Note {
    var latest = try store.note(base.id)
    guard latest.summary == base.summary && latest.summaryRTF == base.summaryRTF else {
      throw NoteError("AI 刚刚更新了这张便签。你的文字仍保留在纸面，请先复制需要保留的文字。")
    }
    latest.summary = text.string
    latest.summaryRTF = try text.data(
      from: NSRange(location: 0, length: text.length),
      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    ).base64EncodedString()
    return try store.save(latest, expected: latest.revision, allowEmpty: true)
  }

  func saveDetail(base: Note, text: NSAttributedString) throws -> Note {
    var latest = try store.note(base.id)
    guard
      latest.details == base.details && latest.richContent == base.richContent
        && latest.attachments == base.attachments
    else {
      throw NoteError("详情刚被另一处更新。当前文字和图片仍在纸面，请先复制保留，再重新打开。")
    }
    latest.details = text.string.replacingOccurrences(of: "\u{fffc}", with: "")
    guard latest.details.count <= 20000 else { throw NoteError("这张纸的文字超过了 20,000 字，请分成几张便签。") }
    var images: [NSTextAttachment] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) {
      value, _, _ in
      if let attachment = value as? NSTextAttachment { images.append(attachment) }
    }
    guard images.count <= 12 else { throw NoteError("一张便签最多放 12 张图片。") }
    latest.attachments = try images.map { attachment in
      guard
        let bytes = attachment.fileWrapper?.regularFileContents
          ?? (attachment.attachmentCell as? NSTextAttachmentCell)?.image?.tiffRepresentation
      else {
        throw NoteError("有一张图片无法保存，请重新粘贴。")
      }
      return try store.importImage(
        data: bytes, name: attachment.fileWrapper?.preferredFilename ?? "图片")
    }
    latest.richContent = try write(text)
    return try store.save(latest, expected: latest.revision, allowEmpty: true)
  }
}
