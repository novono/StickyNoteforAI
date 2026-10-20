import Foundation

let appVersion = "1.3.0"
let summaryLimit = 60
let appID = "local.william.PaperMemory"
let changeEvent = Notification.Name("local.william.PaperMemory.changed")

struct NoteError: LocalizedError {
  var text: String
  var errorDescription: String? { text }
  init(_ text: String) { self.text = text }
}
struct Attachment: Codable, Equatable {
  var id: String
  var name: String
  var file: String
}
struct Note: Codable, Equatable {
  var id = UUID().uuidString.lowercased()
  var summary: String
  var details = ""
  var sourceName = "我"
  var sourceURL = ""
  var category = "未分类"
  var color = "butter"
  var pinned = false
  var completed = false
  var attachments: [Attachment] = []
  var richContent: String? = nil
  var summaryRTF: String? = nil
  var fontSize: Double? = nil
  var fontStyle: String? = nil
  var x: Double? = nil
  var y: Double? = nil
  var createdAt = Date().timeIntervalSince1970
  var updatedAt = Date().timeIntervalSince1970
  var revision = 1
}
struct NoteFile: Codable {
  var version = 1
  var notes: [Note] = []
}
