import AppKit
import Foundation

func launchPaperMemory(openID: String? = nil) {
  if ProcessInfo.processInfo.environment["PAPER_MEMORY_NO_LAUNCH"] == "1" { return }
  // Existing windows already receive the change/open notification. Reopening
  // the app after completing its last note would otherwise create a blank one.
  if NSRunningApplication.runningApplications(withBundleIdentifier: appID).contains(where: {
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated
  }) {
    return
  }
  let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
  let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent()
  guard bundle.pathExtension == "app" else { return }
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  p.arguments = ["-g", bundle.path] + (openID.map { ["--args", "--open", $0] } ?? [])
  p.standardOutput = FileHandle.nullDevice
  p.standardError = FileHandle.nullDevice
  try? p.run()
  p.waitUntilExit()
}

func toolDefinitions() -> [[String: Any]] {
  let string: [String: Any] = ["type": "string"]
  let revision: [String: Any] = [
    "type": "integer", "minimum": 1,
    "description":
      "Revision returned by get/context/list; required to prevent overwriting newer edits.",
  ]
  var content: [String: Any] = [
    "summary": [
      "type": "string", "maxLength": 60,
      "description":
        "Paper front: up to 60 visible characters, at most 6 lines. Newlines supported. Fixed 280×266 pt card; put long context in details.",
    ],
    "details": ["type": "string", "maxLength": 20000],
    "category": [
      "type": "string", "minLength": 1, "maxLength": 16,
      "description":
        "Semantic category. Call paper_context first; reuse existing categories where appropriate.",
    ],
    "sourceName": [
      "type": "string", "maxLength": 40, "description": "Origin, such as Codex, 飞书, or 我.",
    ],
    "sourceURL": ["type": "string", "maxLength": 2048],
    "color": ["type": "string", "enum": ["butter", "rose", "sage", "blue"]],
    "pinned": [
      "type": "boolean", "description": "True floats above apps; false stays at desktop level.",
    ],
  ]
  content["fontSize"] = [
    "type": "number", "enum": [18, 22, 26],
    "description": "Small, medium or large handwriting; default 22.",
  ]
  content["fontStyle"] = [
    "type": "string", "enum": ["kai", "xing", "cao"],
    "description":
      "Bilingual handwriting: kai regular, xing running (default), cao cursive. Applies matching Chinese and English fonts.",
  ]
  func tool(
    _ name: String, _ description: String, _ properties: [String: Any], _ required: [String] = [],
    read: Bool = false
  ) -> [String: Any] {
    [
      "name": "paper_" + name, "description": description,
      "inputSchema": [
        "type": "object", "properties": properties, "required": required,
        "additionalProperties": false,
      ], "annotations": ["readOnlyHint": read, "destructiveHint": false, "openWorldHint": false],
    ]
  }
  var create = content
  create["attachmentPaths"] = [
    "type": "array", "items": ["type": "string"], "maxItems": 12,
    "description":
      "Absolute paths to local screenshots/images. Files are copied into the note's local storage.",
  ]
  content["id"] = string
  content["expectedRevision"] = revision
  let idRev: [String: Any] = ["id": string, "expectedRevision": revision]
  return [
    tool(
      "context",
      "Read existing active notes and category names before classifying or creating a note. Reuse categories based on meaning. Returns newest 100 active notes; use list for more.",
      [:], read: true),
    tool(
      "list",
      "List/search desktop notes; optionally include completed notes or filter by category.",
      ["includeCompleted": ["type": "boolean"], "query": string, "category": string], read: true),
    tool(
      "get", "Read a note and its revision, details and attachment filenames.", ["id": string],
      ["id"], read: true),
    tool(
      "create",
      "Create a real desktop sticky note. Classify from existing context, then pass category. The app opens automatically. Use only when the user wants a note.",
      create, ["summary", "category"]),
    tool(
      "update", "Update selected fields while preserving others; use the current expectedRevision.",
      content, ["id", "expectedRevision"]),
    tool(
      "complete", "Mark a note completed and remove it from the desktop. It remains recoverable.",
      idRev, ["id", "expectedRevision"]),
    tool("restore", "Restore a completed note to the desktop.", idRev, ["id", "expectedRevision"]),
    tool(
      "attach",
      "Copy a local screenshot or image into a note; maximum 20 MB per input and 12 images per note.",
      ["id": string, "expectedRevision": revision, "path": string],
      ["id", "expectedRevision", "path"]),
    tool("open", "Open a note's detail window on the Mac.", ["id": string], ["id"]),
    tool(
      "organize",
      "Apply AI-chosen semantic categories to existing notes as one atomic batch. Read context first. A version conflict leaves the whole batch unchanged.",
      [
        "assignments": [
          "type": "array", "minItems": 1, "maxItems": 100,
          "items": [
            "type": "object",
            "properties": [
              "id": string, "expectedRevision": revision,
              "category": ["type": "string", "minLength": 1, "maxLength": 16],
            ], "required": ["id", "expectedRevision", "category"], "additionalProperties": false,
          ],
        ]
      ], ["assignments"]),
  ]
}

func runMCP() {
  func emit(_ value: [String: Any]) {
    if let bytes = try? JSONSerialization.data(
      withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    {
      FileHandle.standardOutput.write(bytes)
      FileHandle.standardOutput.write(Data([10]))
    }
  }
  while let line = readLine() {
    var requestID: Any = NSNull()
    do {
      guard line.utf8.count <= 2 * 1024 * 1024, let bytes = line.data(using: .utf8),
        let request = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
      else { throw NoteError("Invalid JSON-RPC request") }
      guard let id = request["id"] else { continue }
      requestID = id
      guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
        throw NoteError("Invalid JSON-RPC request")
      }
      let params = request["params"] as? [String: Any] ?? [:]
      var result: [String: Any]
      switch method {
      case "initialize":
        let requested = params["protocolVersion"] as? String ?? "2025-06-18"
        let versions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]
        result = [
          "protocolVersion": versions.contains(requested) ? requested : "2025-06-18",
          "capabilities": ["tools": ["listChanged": false]],
          "serverInfo": ["name": "paper-memory", "version": appVersion],
          "instructions":
            "Desktop sticky notes on the user's Mac. Before creating or organizing, call paper_context and select a category based on existing notes. Do not copy whole conversations into the front; keep it under 60 characters, with details behind it. Only record when requested.",
        ]
      case "ping": result = [:]
      case "tools/list": result = ["tools": toolDefinitions()]
      case "tools/call":
        guard let name = params["name"] as? String,
          let def = toolDefinitions().first(where: { $0["name"] as? String == name })
        else {
          emit(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool"]])
          continue
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
          let required = (def["inputSchema"] as? [String: Any])?["required"] as? [String] ?? []
          guard required.allSatisfy({ args[$0] != nil }) else {
            throw NoteError("缺少必填字段：\(required.joined(separator: ", "))")
          }
          let operation = String(name.dropFirst(6))
          let value = try NoteService(store: .shared).handle(operation, args: args)
          if operation == "open" {
            launchPaperMemory(openID: args["id"] as? String)
          } else if !["get", "list", "context"].contains(operation) {
            launchPaperMemory()
          }
          let payload: [String: Any] = ["ok": true, "data": value]
          let text = String(
            data: try JSONSerialization.data(
              withJSONObject: payload, options: [.withoutEscapingSlashes]), encoding: .utf8)!
          result = [
            "content": [["type": "text", "text": text]], "structuredContent": payload,
            "isError": false,
          ]
        } catch {
          result = [
            "content": [["type": "text", "text": error.localizedDescription]], "isError": true,
          ]
        }
      default:
        emit([
          "jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found"],
        ])
        continue
      }
      emit(["jsonrpc": "2.0", "id": id, "result": result])
    } catch {
      emit([
        "jsonrpc": "2.0", "id": requestID,
        "error": ["code": -32600, "message": error.localizedDescription],
      ])
    }
  }
}
