import AppKit
import CryptoKit

extension Store {
  func attachmentURL(_ a: Attachment) -> URL {
    root.appendingPathComponent("attachments").appendingPathComponent(a.file)
  }
  func importImage(_ url: URL) throws -> Attachment {
    try prepare()
    let attrs = try fm.attributesOfItem(atPath: url.path)
    guard (attrs[.type] as? FileAttributeType) == .typeRegular else { throw NoteError("请选择图片文件。") }
    guard (attrs[.size] as? NSNumber)?.intValue ?? Int.max <= 20 * 1024 * 1024 else {
      throw NoteError("每张图片请小于 20 MB。")
    }
    let bytes = try Data(contentsOf: url)
    return try importImage(data: bytes, name: url.lastPathComponent)
  }
  func importImage(data bytes: Data, name: String) throws -> Attachment {
    try prepare()
    guard bytes.count <= 20 * 1024 * 1024 else { throw NoteError("每张图片请小于 20 MB。") }
    guard let bitmap = NSBitmapImageRep(data: bytes), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0,
      bitmap.pixelsWide <= 20000, bitmap.pixelsHigh <= 20000,
      let png = bitmap.representation(using: .png, properties: [:])
    else { throw NoteError("无法读取这张图片。支持 PNG、JPEG、TIFF 等常见图片。") }
    let id = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
    let a = Attachment(id: id, name: name, file: "\(id).png")
    try png.write(to: attachmentURL(a), options: .atomic)
    return a
  }
}
