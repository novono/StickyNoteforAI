import AppKit
import CryptoKit
import Darwin
import Foundation

final class Store {
  static let shared = Store()
  let root: URL
  let fm = FileManager.default
  let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return e
  }()
  init(root explicitRoot: URL? = nil) {
    if let explicitRoot {
      root = explicitRoot
      return
    }
    if let testRoot = ProcessInfo.processInfo.environment["PAPER_MEMORY_HOME"] {
      root = URL(fileURLWithPath: testRoot, isDirectory: true)
    } else {
      root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PaperMemory", isDirectory: true)
    }
  }
  func prepare() throws {
    try fm.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try fm.createDirectory(
      at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try fm.createDirectory(
      at: root.appendingPathComponent("details"), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
  }
  func transaction<T>(write: Bool = false, _ action: (inout NoteFile) throws -> T) throws -> T {
    try prepare()
    let fd = Darwin.open(root.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, 0o600)
    guard fd >= 0 else { throw NoteError("无法锁定便签数据。") }
    defer {
      flock(fd, LOCK_UN)
      Darwin.close(fd)
    }
    guard flock(fd, LOCK_EX) == 0 else { throw NoteError("便签数据正在使用，请重试。") }
    let file = root.appendingPathComponent("notes.json")
    var data = NoteFile()
    if fm.fileExists(atPath: file.path) {
      do { data = try JSONDecoder().decode(NoteFile.self, from: Data(contentsOf: file)) } catch {
        throw NoteError("便签文件无法读取，已保留原文件：\(file.path)")
      }
    }
    guard data.version == 1 else { throw NoteError("请使用支持此数据版本的贴贴。") }
    let result = try action(&data)
    if write {
      let bytes = try encoder.encode(data)
      if fm.fileExists(atPath: file.path) {
        try Data(contentsOf: file).write(
          to: root.appendingPathComponent("notes.backup.json"), options: .atomic)
      }
      try bytes.write(to: file, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      DistributedNotificationCenter.default().postNotificationName(
        changeEvent, object: root.path, userInfo: nil, deliverImmediately: true)
    }
    return result
  }
  func all() throws -> [Note] { try transaction { $0.notes } }
  func note(_ id: String) throws -> Note {
    guard let note = try all().first(where: { $0.id == id }) else { throw NoteError("找不到这张便签。") }
    return note
  }
  func validate(_ note: Note, allowEmpty: Bool = false) throws {
    guard allowEmpty || !note.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw NoteError("请写一句便签内容。")
    }
    guard note.summary.count <= summaryLimit else {
      throw NoteError("正面最多 \(summaryLimit) 个字；请把其余内容放进详情。")
    }
    guard note.summary.components(separatedBy: "\n").count <= 6 else {
      throw NoteError("正面最多 6 行；较长内容可以放进详情。")
    }
    guard summaryHeight(note.summary, size: 16, script: note.fontStyle ?? "xing") <= 200 else {
      throw NoteError("这些内容超出了纸面，请减少换行或把较长内容移到详情。")
    }
    if let size = note.fontSize {
      guard [18.0, 22.0, 26.0].contains(size) else { throw NoteError("字号支持18、22、26。") }
    }
    if let script = note.fontStyle {
      guard ["kai", "xing", "cao"].contains(script) else { throw NoteError("字体支持楷书、行书和草书。") }
    }
    guard note.details.count <= 20000 else { throw NoteError("详情最多 20,000 个字。") }
    guard note.sourceName.count <= 40 else { throw NoteError("来源名称最多 40 个字。") }
    guard !note.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      note.category.count <= 16
    else { throw NoteError("分类名称需要 1–16 个字。") }
    guard note.sourceURL.count <= 2048 else { throw NoteError("来源链接过长。") }
    if !note.sourceURL.isEmpty {
      guard let u = URL(string: note.sourceURL), let scheme = u.scheme?.lowercased(),
        ["https", "http", "lark", "feishu", "codex"].contains(scheme)
      else { throw NoteError("来源链接支持网页、飞书或 Codex 链接。") }
    }
    guard ["butter", "rose", "sage", "blue"].contains(note.color) else {
      throw NoteError("颜色可选 butter、rose、sage、blue。")
    }
    guard note.attachments.count <= 12 else { throw NoteError("每张便签最多 12 张图片。") }
  }
  func create(_ input: Note, allowEmpty: Bool = false) throws -> Note {
    var n = input
    n.summary = n.summary.trimmingCharacters(in: .whitespacesAndNewlines)
    try validate(n, allowEmpty: allowEmpty)
    return try transaction(write: true) { file in
      file.notes.append(n)
      return n
    }
  }
  func save(_ input: Note, expected: Int, allowEmpty: Bool = false) throws -> Note {
    try validate(input, allowEmpty: allowEmpty)
    return try transaction(write: true) { file in
      guard let i = file.notes.firstIndex(where: { $0.id == input.id }) else {
        throw NoteError("找不到这张便签。")
      }
      guard file.notes[i].revision == expected else {
        throw NoteError("这张便签刚刚被另一处更新了。你的输入仍在窗口中，请先复制需要保留的内容，再重新打开便签。")
      }
      var n = input
      n.x = file.notes[i].x
      n.y = file.notes[i].y
      n.revision = expected + 1
      n.updatedAt = Date().timeIntervalSince1970
      file.notes[i] = n
      return n
    }
  }
  func position(_ id: String, point: NSPoint) throws {
    try transaction(write: true) { file in
      if let i = file.notes.firstIndex(where: { $0.id == id }) {
        file.notes[i].x = point.x
        file.notes[i].y = point.y
      }
    }
  }
  func json<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: encoder.encode(value))
  }
}
