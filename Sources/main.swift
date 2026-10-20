import AppKit
import Foundation

registerPaperFont()

if CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == "--mcp" {
  runMCP()
} else if CommandLine.arguments.count >= 3 && CommandLine.arguments[1] == "--cli" {
  do {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= 2 * 1024 * 1024 else { throw NoteError("输入过大。") }
    let obj = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data)
    guard let args = obj as? [String: Any] else { throw NoteError("输入必须是 JSON 对象。") }
    let result = try NoteService(store: .shared).handle(CommandLine.arguments[2], args: args)
    let bytes = try JSONSerialization.data(
      withJSONObject: ["ok": true, "data": result], options: [.sortedKeys, .withoutEscapingSlashes])
    FileHandle.standardOutput.write(bytes)
    print("")
  } catch {
    let bytes = try! JSONSerialization.data(withJSONObject: [
      "ok": false, "error": error.localizedDescription,
    ])
    FileHandle.standardOutput.write(bytes)
    print("")
    exit(1)
  }
} else {
  let app = NSApplication.shared
  let controller = AppController()
  app.delegate = controller
  app.run()
}
