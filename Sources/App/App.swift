import AppKit
import CoreText
import QuartzCore
import UniformTypeIdentifiers

func showError(_ error: Error) {
  let alert = NSAlert()
  alert.messageText = "没能保存这次修改"
  alert.informativeText = error.localizedDescription
  alert.alertStyle = .warning
  alert.addButton(withTitle: "知道了")
  alert.runModal()
}
func label(_ text: String, frame: NSRect, size: CGFloat = 13, weight: NSFont.Weight = .regular)
  -> NSTextField
{
  let v = NSTextField(labelWithString: text)
  v.frame = frame
  v.font = .systemFont(ofSize: size, weight: weight)
  return v
}
func button(_ title: String, frame: NSRect, target: AnyObject, action: Selector) -> NSButton {
  let b = NSButton(title: title, target: target, action: action)
  b.frame = frame
  b.bezelStyle = .rounded
  return b
}

final class StickyPanel: NSPanel {
  lazy var movement = PaperMovement(window: self)
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .scrollWheel {
      movement.stop()
    }
    super.sendEvent(event)
  }
  override func close() {
    movement.stop()
    super.close()
  }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
  let store: Store
  let windowAnimator: any WindowAnimating
  init(store: Store = .shared, windowAnimator: any WindowAnimating = AppKitWindowAnimator()) {
    self.store = store
    self.windowAnimator = windowAnimator
    super.init()
  }
  var status: NSStatusItem!
  var panels: [String: StickyPanel] = [:]
  var details: [String: DetailController] = [:]
  var library: LibraryController?
  var timer: Timer?
  var hidden = false
  var lastSignature = ""
  var reportedReadError = false
  var reloading = false
  var terminationSignal: DispatchSourceSignal?
  var lastPaperAgeRefresh: TimeInterval = 0
  func refreshPaperAges(now: TimeInterval = Date().timeIntervalSince1970) {
    guard now < lastPaperAgeRefresh || now - lastPaperAgeRefresh >= 60 else { return }
    lastPaperAgeRefresh = now
    for panel in panels.values {
      (panel.contentView as? PaperSurface)?.refreshPaperAge(now: now)
    }
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGTERM, SIG_IGN)
    terminationSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    terminationSignal?.setEventHandler { NSApp.terminate(nil) }
    terminationSignal?.resume()
    NSApp.setActivationPolicy(.accessory)
    createMenus()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(changed), name: changeEvent, object: nil)
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(openRequested(_:)),
      name: Notification.Name("local.william.PaperMemory.open"), object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    reload()
    timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.reload()
      self.refreshPaperAges()
      let request = self.store.root.appendingPathComponent("open-request.json")
      if let bytes = try? Data(contentsOf: request),
        let obj = try? JSONSerialization.jsonObject(with: bytes) as? [String: String],
        let id = obj["id"]
      {
        try? FileManager.default.removeItem(at: request)
        self.edit(id)
      }
    }
    if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1 {
      edit(CommandLine.arguments[i + 1])
    } else if (try? store.all().isEmpty) == true {
      newNote()
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showNotes()
    return false
  }
  func createMenus() {
    let main = NSMenu()
    let app = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "新便签", action: #selector(newNote), keyEquivalent: "n").target = self
    appMenu.addItem(withTitle: "关于贴贴", action: #selector(about), keyEquivalent: "").target = self
    appMenu.addItem(
      withTitle: "退出贴贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    app.submenu = appMenu
    main.addItem(app)
    let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "编辑")
    for (title, sel, key) in [
      ("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
      ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
      ("全选", #selector(NSText.selectAll(_:)), "a"),
    ] { editMenu.addItem(withTitle: title, action: sel, keyEquivalent: key) }
    edit.submenu = editMenu
    main.addItem(edit)
    NSApp.mainMenu = main
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "贴贴便签")
    status.button?.toolTip = "贴贴 · 桌面上的短时记忆"
    let menu = NSMenu()
    for (title, sel, key) in [
      ("写一张便签…", #selector(newNote), "n"), ("所有便签…", #selector(showLibrary), ""),
      ("显示桌面便签", #selector(showNotes), ""), ("暂时隐藏便签", #selector(hideNotes), ""),
    ] {
      let i = menu.addItem(withTitle: title, action: sel, keyEquivalent: key)
      i.target = self
    }
    menu.addItem(.separator())
    menu.addItem(withTitle: "打开数据文件夹", action: #selector(openData), keyEquivalent: "").target = self
    menu.addItem(withTitle: "使用说明", action: #selector(showHelp), keyEquivalent: "").target = self
    menu.addItem(withTitle: "关于贴贴", action: #selector(about), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "退出贴贴", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    status.menu = menu
  }
  @objc func changed(_ notification: Notification) {
    guard notification.object == nil || notification.object as? String == store.root.path else {
      return
    }
    reload()
  }
  @objc func openRequested(_ notification: Notification) {
    let scopedID =
      notification.object as? String == store.root.path
      ? notification.userInfo?["id"] as? String : nil
    // Accept older clients only when their note exists in this store.
    if let id = scopedID ?? notification.object as? String, (try? store.note(id)) != nil {
      reload()
      edit(id)
    }
  }
  @objc func screenChanged() {
    for panel in panels.values {
      panel.movement.stop()
      let origin = PaperGlide.containedOrigin(
        panel.frame.origin, size: panel.frame.size,
        screens: NSScreen.screens.map(\.visibleFrame))
      if origin != panel.frame.origin {
        panel.setFrameOrigin(origin)
        movementDidSettle(panel)
      }
    }
    lastSignature = ""
    reload()
  }
  func reload() {
    guard !reloading else { return }
    reloading = true
    defer { reloading = false }
    do {
      let notes = try store.all()
      let signature = notes.map { "\($0.id):\($0.revision):\($0.completed)" }.joined(separator: ",")
      guard signature != lastSignature || panels.isEmpty && !notes.isEmpty else { return }
      lastSignature = signature
      reportedReadError = false
      let active = notes.filter { !$0.completed }
      for id in Array(panels.keys) where !active.contains(where: { $0.id == id }) {
        guard let panel = panels[id] else { continue }
        panel.movement.stop()
        PaperMotion.finish(panel)
        if let detail = details[id] {
          guard detail.saveDraft() else { continue }
          detail.prepareForRemoval()
        } else if let front = panel.contentView as? PaperView, !front.saveDraft() {
          continue
        }
        panels.removeValue(forKey: id)
        details.removeValue(forKey: id)
        animateTear(panel)
      }
      for (index, note) in active.enumerated() {
        if let p = panels[note.id] {
          p.title = "贴贴 · \(note.summary)"
          if let detail = details[note.id] {
            let returnToDesktop = detail.note.pinned && !note.pinned
            detail.refresh(note)
            if returnToDesktop { detail.collapse() }
          } else {
            (p.contentView as? PaperView)?.refresh(note)
            configureLevel(p, pinned: note.pinned)
          }
        } else {
          let p = StickyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 266),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
          p.title = "贴贴 · \(note.summary)"
          p.identifier = NSUserInterfaceItemIdentifier(note.id)
          p.isFloatingPanel = false
          p.hidesOnDeactivate = false
          p.isReleasedWhenClosed = false
          p.hasShadow = true
          p.backgroundColor = .clear
          p.isOpaque = false
          p.animationBehavior = .utilityWindow
          p.delegate = self
          p.movement.onSettled = { [weak self, weak p] _ in
            guard let self, let p, self.panels[note.id] === p else { return }
            self.movementDidSettle(p)
          }
          p.contentView = PaperView(note: note, owner: self)
          configureLevel(p, pinned: note.pinned)
          let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
          let cols = max(1, Int(visible.width / 304))
          let col = index % cols
          let row = (index / cols) % max(1, Int(visible.height / 290))
          var point = NSPoint(
            x: note.x ?? Double(visible.maxX - 302 - CGFloat(col * 300)),
            y: note.y ?? Double(visible.maxY - 290 - CGFloat(row * 286)))
          let rect = NSRect(origin: point, size: p.frame.size)
          if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(rect) }) {
            point.x = min(max(visible.minX, point.x), visible.maxX - 280)
            point.y = min(max(visible.minY, point.y), visible.maxY - 266)
          }
          p.setFrameOrigin(point)
          panels[note.id] = p
          if !hidden { animateStick(p) }
        }
      }
      library?.refresh()
    } catch {
      if !reportedReadError {
        reportedReadError = true
        showError(error)
      }
    }
  }
  func configureLevel(_ p: NSWindow, pinned: Bool) {
    NoteWindowPolicy.apply(to: p, pinned: pinned)
  }
  func animateStick(_ p: NSPanel) {
    PaperMotion.play(.stick, on: p) { [weak self, weak p] in
      guard let self, let p, let id = p.identifier?.rawValue, self.panels[id] === p else { return }
      if let view = p.contentView as? PaperView {
        if let latest = try? self.store.note(id) { view.refresh(latest) }
        if p.isKeyWindow { p.makeFirstResponder(view.textView) }
      }
    }
  }
  func animateTear(_ p: NSPanel) { PaperMotion.play(.tear, on: p) }
  func windowDidMove(_ notification: Notification) {
    guard let p = notification.object as? StickyPanel, let id = p.identifier?.rawValue,
      panels[id] != nil, !PaperMotion.isAnimating(p), !p.movement.isActive
    else { return }
    do { try store.position(id, point: p.frame.origin) } catch { showError(error) }
  }
  func movementDidSettle(_ panel: StickyPanel) {
    guard let id = panel.identifier?.rawValue else { return }
    let origin = details[id]?.settledOrigin(afterMoving: panel.frame) ?? panel.frame.origin
    do { try store.position(id, point: origin) } catch { showError(error) }
  }
  func mutate(_ id: String, action: (inout Note) -> Void) {
    panels[id]?.movement.stop()
    do {
      var n = try store.note(id)
      let rev = n.revision
      action(&n)
      _ = try store.save(n, expected: rev, allowEmpty: true)
      reload()
    } catch { showError(error) }
  }
  func attach(_ id: String, urls: [URL]) {
    do {
      var n = try store.note(id)
      let rev = n.revision
      guard n.attachments.count + urls.count <= 12 else { throw NoteError("每张便签最多 12 张图片。") }
      let documents = NoteDocuments(store: store)
      let rich = n.richContent != nil ? documents.detail(n) : nil
      for url in urls {
        let attachment = try store.importImage(url)
        n.attachments.append(attachment)
        if let rich { documents.append(attachment, to: rich) }
      }
      if let rich { n.richContent = try documents.write(rich) }
      _ = try store.save(n, expected: rev, allowEmpty: true)
      reload()
    } catch { showError(error) }
  }
  func edit(_ id: String) {
    panels[id]?.movement.stop()
    if let d = details[id] {
      d.showWindow(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    do {
      var n = try store.note(id)
      if n.completed {
        n.completed = false
        _ = try store.save(n, expected: n.revision, allowEmpty: true)
        reload()
      }
      guard let panel = panels[id] else { return }
      PaperMotion.finish(panel)
      if let front = panels[id]?.contentView as? PaperView {
        guard front.saveDraft() else { return }
        n = try store.note(id)
      }
      let d = DetailController(note: n, isNew: false, owner: self)
      details[id] = d
      NSApp.activate(ignoringOtherApps: true)
      d.showWindow(nil)
    } catch { showError(error) }
  }
  @objc func newNote() {
    do {
      var n = Note(summary: "")
      n.pinned = true
      n = try store.create(n, allowEmpty: true)
      hidden = false
      reload()
      if let p = panels[n.id] {
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let view = p.contentView as? PaperView { p.makeFirstResponder(view.textView) }
      }
    } catch { showError(error) }
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    for p in panels.values {
      p.movement.stop()
      PaperMotion.finish(p)
      if let v = p.contentView as? PaperView, !v.saveDraft() { return .terminateCancel }
    }
    for d in Array(details.values) { if !d.saveDraft() { return .terminateCancel } }
    return .terminateNow
  }
  @objc func showLibrary() {
    if library == nil { library = LibraryController(owner: self) }
    library?.refresh()
    library?.showWindow(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func showNotes() {
    hidden = false
    reload()
    for p in panels.values { p.orderFrontRegardless() }
  }
  @objc func hideNotes() {
    hidden = true
    panels.values.forEach {
      $0.movement.stop()
      $0.orderOut(nil)
    }
  }
  @objc func openData() { NSWorkspace.shared.open(store.root) }
  @objc func showHelp() {
    if let url = Bundle.main.url(forResource: "使用说明", withExtension: "html") {
      NSWorkspace.shared.open(url)
    }
  }
  @objc func about() {
    let a = NSAlert()
    a.messageText = "贴贴 · PaperMemory"
    a.informativeText =
      "桌面上的短时记忆\n\n直接在纸面写字，自动保存。\n右下角展开，右上角缩小。\n右键新建、删除或放到桌面。\n\n版本 \(appVersion) · 数据保存在本机。"
    a.addButton(withTitle: "好")
    a.runModal()
  }
}
