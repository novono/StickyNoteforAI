import AppKit
import QuartzCore

final class PaperView: PaperSurface, NSTextViewDelegate {
  var note: Note
  var store: Store { coordinator?.store ?? .shared }
  weak var coordinator: AppController?
  let textView = PaperTextView()
  let more = NSButton(), expand = NSButton()
  lazy var lockButton = paperLockButton(target: self, action: #selector(unlockPaper))
  var saveTimer: Timer?
  var dirty = false
  var applying = false
  var tracking: NSTrackingArea?
  init(note: Note, owner: AppController) {
    self.note = note
    self.coordinator = owner
    super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 266))
    colorKey = note.color
    paperAppearance = PaperAppearance(id: note.id)
    textView.frame = NSRect(x: 24, y: 24, width: 232, height: 210)
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.isRichText = true
    textView.plainOnly = true
    textView.importsGraphics = false
    textView.usesInspectorBar = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.isVerticallyResizable = false
    textView.isHorizontallyResizable = false
    textView.delegate = self
    textView.insertionPointColor = ink
    textView.textColor = ink
    textView.setAccessibilityLabel("便签正文")
    textView.closeEditor = { [weak self] in self?.window?.makeFirstResponder(nil) }
    textView.contextMenu = { [weak self] in self?.paperMenu() ?? NSMenu() }
    addSubview(textView)
    for (b, symbol, tip, x, y, sel) in [
      (more, "circle.lefthalf.filled", "颜色与字号", CGFloat(8), CGFloat(239), #selector(options)),
      (
        expand, "arrow.up.left.and.arrow.down.right", "详情", CGFloat(243), CGFloat(8),
        #selector(showDetail)
      ),
    ] {
      b.frame = NSRect(x: x, y: y, width: 24, height: 23)
      b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
      b.imagePosition = .imageOnly
      b.isBordered = false
      b.contentTintColor = ink.withAlphaComponent(0.6)
      b.toolTip = tip
      b.setAccessibilityLabel(tip)
      b.target = self
      b.action = sel
      b.alphaValue = b === expand ? 0.16 : 0.001
      addSubview(b)
    }
    lockButton.frame = NSRect(x: bounds.width - 31, y: bounds.height - 29, width: 22, height: 22)
    addSubview(lockButton)
    registerForDraggedTypes([.fileURL])
    refresh(note)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self,
      userInfo: nil)
    addTrackingArea(tracking!)
  }
  override func mouseEntered(with event: NSEvent) {
    NSAnimationContext.runAnimationGroup { c in
      c.duration = 0.15
      [more, expand].forEach { $0.animator().alphaValue = 1 }
    }
  }
  override func mouseExited(with event: NSEvent) {
    NSAnimationContext.runAnimationGroup { c in
      c.duration = 0.18
      [more].forEach { $0.animator().alphaValue = 0.001 }
      expand.animator().alphaValue = 0.16
    }
  }
  func refresh(_ n: Note) {
    paperCreatedAt = n.createdAt
    lockButton.isHidden = !n.pinned
    note.pinned = n.pinned
    guard !dirty else { return }
    note = n
    colorKey = n.color
    applying = true
    if let b64 = n.summaryRTF, let data = Data(base64Encoded: b64),
      let rich = try? NSAttributedString(
        data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil), rich.string == n.summary
    {
      textView.textStorage?.setAttributedString(rich)
    } else {
      textView.string = n.summary
    }
    fitText()
    applying = false
  }
  func fitText() {
    var size: CGFloat = note.fontSize ?? 22
    while size > 16
      && summaryHeight(textView.string, size: size, script: note.fontStyle ?? "xing") > 200
    { size -= 1 }
    textView.font = paperFont(size, script: note.fontStyle ?? "xing")
    let p = NSMutableParagraphStyle()
    p.lineSpacing = 3
    p.lineBreakMode = .byWordWrapping
    textView.defaultParagraphStyle = p
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: size, script: note.fontStyle ?? "xing")
    }
    textView.typingAttributes = summaryStyle(size, script: note.fontStyle ?? "xing")
  }
  func textView(
    _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    guard let s = replacementString, let range = Range(affectedCharRange, in: textView.string)
    else { return true }
    let proposed = textView.string.replacingCharacters(in: range, with: s)
    if proposed.count > 60 || proposed.components(separatedBy: "\n").count > 6
      || summaryHeight(proposed, size: note.fontSize ?? 22, script: note.fontStyle ?? "xing") > 200
    {
      NSSound.beep()
      return false
    }
    return true
  }
  func textDidChange(_ notification: Notification) {
    guard !applying else { return }
    dirty = true
    guard !textView.hasMarkedText() else { return }
    applying = true
    fitText()
    applying = false
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
      _ = self?.saveDraft()
    }
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    if !applying { textView.scheduleSelectionMenu() }
  }
  @discardableResult func saveDraft() -> Bool {
    saveTimer?.invalidate()
    guard dirty else { return true }
    do {
      guard let storage = textView.textStorage else { return false }
      note = try NoteDocuments(store: store).saveSummary(base: note, text: storage)
      dirty = false
      coordinator?.reload()
      return true
    } catch {
      showError(error)
      return false
    }
  }
  @objc func showDetail() { if saveDraft() { coordinator?.edit(note.id) } }
  @objc func togglePin() { if saveDraft() { coordinator?.mutate(note.id) { $0.pinned.toggle() } } }
  @objc func unlockPaper() {
    if saveDraft() { coordinator?.mutate(note.id) { $0.pinned = false } }
  }
  @objc func markComplete() {
    if saveDraft() { coordinator?.mutate(note.id) { $0.completed = true } }
  }
  @objc func options() {
    let menu = styleMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 8, y: 237), in: self)
  }
  func styleMenu() -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (key, name, _) in paperColors {
      let i = menu.addItem(withTitle: name, action: #selector(setColor(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = key
      i.state = key == note.color ? .on : .off
    }
    menu.addItem(.separator())
    for (name, size) in [("小号 · 18", 18.0), ("中号 · 22", 22.0), ("大号 · 26", 26.0)] {
      let i = menu.addItem(withTitle: name, action: #selector(setFontSize(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = size
      i.state = (note.fontSize ?? 22) == size ? .on : .off
      i.isEnabled =
        summaryHeight(textView.string, size: size, script: note.fontStyle ?? "xing") <= 200
    }
    menu.addItem(.separator())
    for (key, name) in paperScripts {
      let i = menu.addItem(withTitle: name, action: #selector(setFontStyle(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = key
      i.state = (note.fontStyle ?? "xing") == key ? .on : .off
    }
    return menu
  }
  func paperMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: "新建便签", action: #selector(AppController.newNote), keyEquivalent: "")
      .target = coordinator
    menu.addItem(withTitle: "展开", action: #selector(showDetail), keyEquivalent: "").target = self
    menu.addItem(.separator())
    let style = menu.addItem(withTitle: "颜色与字号", action: nil, keyEquivalent: "")
    style.submenu = styleMenu()
    menu.addItem(
      withTitle: note.pinned ? "改为桌面小组件" : "浮在窗口上方", action: #selector(togglePin), keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "删除便签", action: #selector(markComplete), keyEquivalent: "").target =
      self
    return menu
  }
  override func menu(for event: NSEvent) -> NSMenu? { paperMenu() }
  @objc func setColor(_ sender: NSMenuItem) {
    if saveDraft(), let color = sender.representedObject as? String {
      coordinator?.mutate(note.id) { $0.color = color }
    }
  }
  @objc func setFontSize(_ sender: NSMenuItem) {
    if saveDraft(), let size = sender.representedObject as? Double {
      coordinator?.mutate(note.id) { $0.fontSize = size }
    }
  }
  @objc func setFontStyle(_ sender: NSMenuItem) {
    if saveDraft(), let script = sender.representedObject as? String {
      coordinator?.mutate(note.id) { $0.fontStyle = script }
    }
  }
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard saveDraft(),
      let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    else { return false }
    coordinator?.attach(note.id, urls: urls)
    return true
  }
}
