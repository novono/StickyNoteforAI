import AppKit
import CoreText
import QuartzCore

@main struct WindowStateTests {
  static func main() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    Task { @MainActor in
      do { try await verify() } catch { fatalError("Window state verification failed: \(error)") }
      NSApp.stop(nil)
      if let wake = NSEvent.otherEvent(
        with: .applicationDefined, location: .zero, modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
        context: nil, subtype: 0, data1: 0, data2: 0)
      {
        NSApp.postEvent(wake, atStart: false)
      }
    }
    NSApp.run()
  }
  @MainActor static func verify() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let store = Store(root: root)
    let service = NoteService(store: store)
    let documents = NoteDocuments(store: store)
    let animator = ControlledWindowAnimator()
    let owner = AppController(store: store, windowAnimator: animator)
    // Keep the native event loop running continuously so AppKit can finish
    // implicit animation transactions between user actions.
    func settle(_ seconds: Double = 0.4) async {
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    func command(_ operation: String, id: String, fields: [String: Any] = [:]) throws -> Note {
      let current = try store.note(id)
      var args = fields
      args["id"] = id
      args["expectedRevision"] = current.revision
      _ = try service.handle(operation, args: args)
      return try store.note(id)
    }
    var note = Note(summary: "桌面模式验证\nDesktop paper")
    note.pinned = true
    note.details = "原来的详情"
    note = try store.create(note)
    owner.reload()
    let panel = owner.panels[note.id]!
    PaperMotion.finish(panel)
    let originalFrame = panel.frame
    precondition(panel.level == .floating)
    let front = panel.contentView as! PaperView
    precondition(!front.lockButton.isHidden)
    front.unlockPaper()
    precondition(front.lockButton.isHidden && panel.level.rawValue == -1)
    precondition((try? store.note(note.id).pinned) == false)
    note = try command("update", id: note.id, fields: ["pinned": true])
    owner.reload()
    precondition(!front.lockButton.isHidden && panel.level == .floating)
    note = try command("update", id: note.id, fields: ["pinned": false])
    owner.reload()
    precondition(
      panel.isVisible && panel.level.rawValue == -1 && !panel.hidesOnDeactivate && !panel.canHide)
    precondition(
      panel.collectionBehavior.contains(.stationary)
        && panel.collectionBehavior.contains(.canJoinAllSpaces))
    precondition(!panel.collectionBehavior.contains(.fullScreenAuxiliary))
    precondition(panel.frame == originalFrame && owner.panels[note.id] === panel)
    // Actual WindowServer ordering, not just the saved mode flag.
    await settle(0.1)
    let info =
      CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(panel.windowNumber))
      as! [[String: Any]]
    precondition(info.first?[kCGWindowLayer as String] as? Int == -1, "WindowServer: \(info)")
    owner.hideNotes()
    precondition(!panel.isVisible)
    owner.showNotes()
    precondition(panel.isVisible && panel.level.rawValue == -1)
    owner.edit(note.id)
    let detail = owner.details[note.id]!
    precondition(!(panel.contentView as! PaperSurface).allowsDragging)
    animator.finish()
    precondition((panel.contentView as! PaperSurface).allowsDragging, "Expansion did not complete")
    precondition(detail.window === panel && panel.level == .floating)
    precondition(detail.lockButton.isHidden, "Temporary expanded editing is not a pinned note")
    note = try command(
      "update", id: note.id, fields: ["details": "AI 更新已展开的详情\nUpdated while open"])
    owner.reload()
    precondition(detail.textView.string == note.details)
    detail.textView.insertText(
      "\n手动补充", replacementRange: NSRange(location: detail.textView.textStorage!.length, length: 0))
    _ = try command("update", id: note.id, fields: ["color": "sage"])
    owner.reload()
    precondition(detail.textView.string.hasSuffix("手动补充"))
    precondition(detail.saveDraft())
    note = try store.note(note.id)
    precondition(note.color == "sage" && note.details.hasSuffix("手动补充"))
    note = try command("update", id: note.id, fields: ["pinned": true])
    owner.reload()
    precondition(!detail.lockButton.isHidden)
    let shrink = panel.contentView!.subviews.compactMap { $0 as? NSButton }.first {
      $0.action == #selector(DetailController.shrink)
    }!
    precondition(!shrink.frame.intersects(detail.lockButton.frame))
    detail.textView.insertText(
      "\n解锁保留草稿",
      replacementRange: NSRange(location: detail.textView.textStorage!.length, length: 0))
    // Text input and the subsequent button click are distinct AppKit events.
    await settle(0.02)
    precondition(detail.dirty)
    detail.unlockPaper()
    precondition(detail.collapsing && owner.details[note.id] === detail)
    animator.finish()
    precondition(
      owner.details[note.id] == nil && panel.level.rawValue == -1 && panel.frame == originalFrame,
      "Unlock: detail=\(owner.details[note.id] != nil), collapsing=\(detail.collapsing), pinned=\(String(describing: try? store.note(note.id).pinned)), level=\(panel.level.rawValue), frame=\(panel.frame), expected=\(originalFrame)"
    )
    note = try store.note(note.id)
    precondition(!note.pinned && note.details.hasSuffix("解锁保留草稿"))
    precondition((panel.contentView as! PaperView).lockButton.isHidden)
    // A completion during collapse must not reinsert the old editor/panel.
    owner.edit(note.id)
    animator.finish()
    owner.details[note.id]!.collapse()
    _ = try command("complete", id: note.id)
    owner.reload()
    animator.finish()  // A late animation callback must not resurrect the editor.
    await settle(0.9)
    precondition(owner.panels[note.id] == nil && owner.details[note.id] == nil && !panel.isVisible)
    // Empty GUI-created notes still support AI management operations.
    let blank = try store.create(Note(summary: ""), allowEmpty: true)
    let archived = try command("complete", id: blank.id)
    precondition(archived.completed)
    _ = try command("restore", id: blank.id)
    let blankNow = try store.note(blank.id)
    _ = try service.handle(
      "organize",
      args: [
        "assignments": [["id": blank.id, "expectedRevision": blankNow.revision, "category": "空白纸"]]
      ])
    precondition((try? store.note(blank.id).category) == "空白纸")
    // AI attachments preserve the existing document's inline formatting.
    var richNote = try store.create(Note(summary: "图文排版保留"))
    let content = NSMutableAttributedString(string: "已完成的步骤\n保留这段排版", attributes: summaryStyle(22))
    content.addAttribute(.strikethroughStyle, value: 1, range: NSRange(location: 0, length: 3))
    richNote = try documents.saveDetail(base: richNote, text: content)
    richNote = try command("attach", id: richNote.id, fields: ["path": CommandLine.arguments[2]])
    let loaded = documents.detail(richNote)
    precondition((loaded.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == 1)
    var images = 0
    loaded.enumerateAttribute(.attachment, in: NSRange(location: 0, length: loaded.length)) {
      value, _, _ in if value != nil { images += 1 }
    }
    precondition(images == 1 && loaded.string.contains("保留这段排版"))
    let baseline = richNote
    _ = try command("update", id: richNote.id, fields: ["details": "另一次 AI 更新"])
    do {
      _ = try documents.saveDetail(base: baseline, text: loaded)
      preconditionFailure("A stale draft overwrote an AI update")
    } catch is NoteError {}
    precondition((try? store.note(richNote.id).details) == "另一次 AI 更新")
    // App instances receive only events for their own store.
    let other = Store(root: root.appendingPathComponent("other"))
    _ = try other.create(Note(summary: "隔离数据"))
    let signature = owner.lastSignature
    owner.changed(Notification(name: changeEvent, object: other.root.path))
    precondition(owner.lastSignature == signature)
    print(
      "PASS: desktop WindowServer layer/visibility, hide/show, same-panel expand/collapse, live AI detail refresh, draft merge, delete-during-collapse, blank-note AI management, rich attachment preservation, stale-draft protection, isolated stores"
    )
  }
}
