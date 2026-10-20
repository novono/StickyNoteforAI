import AppKit

/// Shared command boundary for MCP and the CLI; storage knows no transport fields.
struct NoteService {
  let store: Store
  func handle(_ method: String, args: [String: Any]) throws -> Any {
    let allowed: [String: Set<String>] = [
      "health": [], "list": ["includeCompleted", "query", "category"], "get": ["id"], "context": [],
      "organize": ["assignments"],
      "create": [
        "summary", "details", "sourceName", "sourceURL", "category", "color", "pinned",
        "attachmentPaths", "fontSize", "fontStyle",
      ],
      "update": [
        "id", "expectedRevision", "summary", "details", "sourceName", "sourceURL", "category",
        "color", "pinned", "fontSize", "fontStyle",
      ],
      "complete": ["id", "expectedRevision"], "restore": ["id", "expectedRevision"],
      "attach": ["id", "expectedRevision", "path"], "open": ["id"],
    ]
    guard let fields = allowed[method] else { throw NoteError("未知操作：\(method)") }
    guard Set(args.keys).isSubset(of: fields) else { throw NoteError("输入包含未知字段。") }
    func string(_ key: String, required: Bool = false) throws -> String? {
      if let v = args[key] {
        guard let s = v as? String else { throw NoteError("\(key) 必须是文本。") }
        return s
      }
      if required { throw NoteError("缺少 \(key)。") }
      return nil
    }
    for key in [
      "summary", "details", "sourceName", "sourceURL", "category", "color", "id", "path", "query",
      "fontStyle",
    ] where args[key] != nil { _ = try string(key) }
    for key in ["pinned", "includeCompleted"] where args[key] != nil {
      guard let v = args[key] as? NSNumber, CFGetTypeID(v) == CFBooleanGetTypeID() else {
        throw NoteError("\(key) 必须是布尔值。")
      }
    }
    if let value = args["fontSize"] {
      guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
        [18.0, 22.0, 26.0].contains(n.doubleValue)
      else { throw NoteError("fontSize 只能是18、22或26。") }
    }
    if method == "health" {
      return [
        "app": "贴贴 PaperMemory", "version": appVersion, "summaryLimit": summaryLimit,
        "dataPath": store.root.path,
      ] as [String: Any]
    }
    if method == "context" {
      let notes = try store.all().filter { !$0.completed }.sorted { $0.updatedAt > $1.updatedAt }
      return [
        "categories": Array(Set(notes.map { $0.category })).sorted(),
        "notes": try store.json(Array(notes.prefix(100))), "totalActive": notes.count,
        "instruction":
          "根据已有便签语义选择已有分类；没有合适分类再建简短分类。创建时传 category，整理已有便签用 organize，并提供每条 expectedRevision。",
      ] as [String: Any]
    }
    if method == "organize" {
      guard let rows = args["assignments"] as? [[String: Any]], !rows.isEmpty, rows.count <= 100
      else { throw NoteError("assignments 需要 1–100 条分类分配。") }
      let updated = try store.transaction(write: true) { file -> [Note] in
        var results: [Note] = []
        var ids = Set<String>()
        for row in rows {
          guard Set(row.keys) == Set(["id", "category", "expectedRevision"]),
            let id = row["id"] as? String, ids.insert(id).inserted,
            let category = row["category"] as? String,
            let rev = row["expectedRevision"] as? NSNumber,
            CFGetTypeID(rev) != CFBooleanGetTypeID(), rev.doubleValue == Double(rev.intValue),
            let i = file.notes.firstIndex(where: { $0.id == id })
          else { throw NoteError("分类分配格式不正确，或便签不存在/重复。") }
          guard file.notes[i].revision == rev.intValue else {
            throw NoteError("分类时发现版本冲突，请重新读取后重试。")
          }
          file.notes[i].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
          file.notes[i].revision += 1
          file.notes[i].updatedAt = Date().timeIntervalSince1970
          try store.validate(file.notes[i], allowEmpty: true)
          results.append(file.notes[i])
        }
        return results
      }
      return try store.json(updated)
    }
    if method == "list" {
      let q = (try string("query") ?? "").lowercased()
      let category = try string("category")
      let notes = try store.all().filter {
        (args["includeCompleted"] as? Bool == true || !$0.completed)
          && (category == nil || $0.category == category)
          && (q.isEmpty
            || "\($0.summary) \($0.details) \($0.sourceName) \($0.category)".lowercased().contains(
              q))
      }
      return try store.json(notes)
    }
    if method == "create" {
      var n = Note(summary: try string("summary", required: true)!)
      n.sourceName = "AI"
      try apply(args, to: &n)
      try store.validate(n)
      if let raw = args["attachmentPaths"] {
        guard let paths = raw as? [String], paths.count <= 12 else {
          throw NoteError("attachmentPaths 必须是最多 12 个本地图片路径。")
        }
        for path in paths {
          n.attachments.append(try store.importImage(URL(fileURLWithPath: path)))
        }
      }
      return try store.json(store.create(n))
    }
    let id = try string("id", required: true)!
    var n = try store.note(id)
    if method == "get" { return try store.json(n) }
    if method == "open" {
      try JSONSerialization.data(withJSONObject: ["id": id]).write(
        to: store.root.appendingPathComponent("open-request.json"), options: .atomic)
      DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("local.william.PaperMemory.open"), object: store.root.path,
        userInfo: ["id": id], deliverImmediately: true)
      return ["id": id, "requested": true]
    }
    guard let num = args["expectedRevision"] as? NSNumber, CFGetTypeID(num) != CFBooleanGetTypeID(),
      num.doubleValue == Double(num.intValue), num.intValue > 0
    else { throw NoteError("修改前请读取便签，并传入 expectedRevision。") }
    guard n.revision == num.intValue else { throw NoteError("版本冲突：请重新读取便签后再修改。") }
    if method == "complete" { n.completed = true }
    if method == "restore" { n.completed = false }
    if method == "update" { try apply(args, to: &n) }
    if method == "attach" {
      guard n.attachments.count < 12 else { throw NoteError("每张便签最多 12 张图片。") }
      let attachment = try store.importImage(
        URL(fileURLWithPath: try string("path", required: true)!))
      if n.richContent != nil {
        let documents = NoteDocuments(store: store)
        let text = documents.detail(n)
        documents.append(attachment, to: text)
        n.richContent = try documents.write(text)
      }
      n.attachments.append(attachment)
    }
    return try store.json(
      store.save(
        n, expected: num.intValue, allowEmpty: method != "update" || args["summary"] == nil))
  }
  func apply(_ args: [String: Any], to n: inout Note) throws {
    if let s = args["summary"] as? String {
      n.summary = s
      n.summaryRTF = nil
    }
    if let s = args["details"] as? String {
      n.details = s
      n.richContent = nil
    }
    if let s = args["sourceName"] as? String { n.sourceName = s }
    if let s = args["sourceURL"] as? String { n.sourceURL = s }
    if let s = args["category"] as? String {
      n.category = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let s = args["color"] as? String { n.color = s }
    if let p = args["pinned"] as? Bool { n.pinned = p }
    if let size = args["fontSize"] as? NSNumber { n.fontSize = size.doubleValue }
    if let script = args["fontStyle"] as? String { n.fontStyle = script }
  }
}
