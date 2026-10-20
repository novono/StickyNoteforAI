import AppKit

final class DetailController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
  var store: Store { coordinator?.store ?? .shared }
  weak var coordinator: AppController?
  var note: Note
  var isNew: Bool
  let textView = PaperTextView()
  lazy var lockButton = paperLockButton(target: self, action: #selector(unlockPaper))
  var dirty = false
  var saveTimer: Timer?
  var saving = false
  var collapsing = false
  var expanded = false
  var collapsedFrame: NSRect
  var expandedFrame: NSRect
  let scroll = NSScrollView()
  init(note: Note, isNew: Bool, owner: AppController) {
    self.note = note
    self.isNew = isNew
    coordinator = owner
    let w = owner.panels[note.id]!
    collapsedFrame = w.frame
    let screen = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
    let width = min(CGFloat(620), screen.width - 40)
    let height = min(CGFloat(650), screen.height - 40)
    expandedFrame = NSRect(
      x: min(max(screen.minX + 20, w.frame.midX - width / 2), screen.maxX - width - 20),
      y: min(max(screen.minY + 20, w.frame.midY - height / 2), screen.maxY - height - 20),
      width: width, height: height)
    super.init(window: w)
    w.delegate = self
    w.level = .floating
    let surface = PaperSurface(frame: w.contentView!.bounds)
    surface.colorKey = note.color
    surface.paperAppearance = PaperAppearance(id: note.id)
    surface.paperCreatedAt = note.createdAt
    surface.allowsDragging = false
    w.contentView = surface
    surface.onDoubleClick = { [weak self] in self?.collapse() }
    scroll.frame = surface.bounds.insetBy(dx: 28, dy: 28)
    scroll.autoresizingMask = [.width, .height]
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    scroll.alphaValue = 0
    textView.frame = scroll.bounds
    textView.minSize = NSSize(width: 0, height: scroll.bounds.height)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.containerSize = NSSize(
      width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.isRichText = true
    textView.importsGraphics = true
    textView.allowsImageEditing = true
    textView.usesInspectorBar = false
    textView.usesFontPanel = false
    textView.drawsBackground = false
    textView.textContainerInset = NSSize(width: 0, height: 8)
    textView.font = paperFont(note.fontSize ?? 22, script: note.fontStyle ?? "xing")
    textView.textColor = ink
    textView.insertionPointColor = ink
    textView.textStorage?.setAttributedString(NoteDocuments(store: store).detail(note))
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: note.fontSize ?? 22, script: note.fontStyle ?? "xing")
    }
    textView.typingAttributes = summaryStyle(note.fontSize ?? 22, script: note.fontStyle ?? "xing")
    textView.resizeImages()
    textView.delegate = self
    textView.closeEditor = { [weak self] in self?.collapse() }
    textView.setAccessibilityLabel("便签详情，可直接写字和粘贴图片")
    textView.contextMenu = { [weak self] in self?.paperMenu() ?? NSMenu() }
    surface.contextActions = { [weak self] in self?.paperMenu() ?? NSMenu() }
    scroll.documentView = textView
    surface.addSubview(scroll)
    w.initialFirstResponder = textView
    let shrinkButton = NSButton(
      frame: NSRect(
        x: surface.bounds.width - 31, y: surface.bounds.height - 29, width: 22, height: 22))
    shrinkButton.image = NSImage(
      systemSymbolName: "arrow.down.right.and.arrow.up.left", accessibilityDescription: "缩小便签")
    shrinkButton.imagePosition = .imageOnly
    shrinkButton.isBordered = false
    shrinkButton.contentTintColor = ink.withAlphaComponent(0.45)
    shrinkButton.autoresizingMask = [.minXMargin, .minYMargin]
    shrinkButton.target = self
    shrinkButton.action = #selector(shrink)
    shrinkButton.toolTip = "缩小"
    shrinkButton.setAccessibilityLabel("缩小便签")
    surface.addSubview(shrinkButton)
    lockButton.frame = NSRect(
      x: surface.bounds.width - 57, y: surface.bounds.height - 29, width: 22, height: 22)
    lockButton.isHidden = !note.pinned
    surface.addSubview(lockButton)
    let styleButton = NSButton(
      frame: NSRect(x: 8, y: surface.bounds.height - 29, width: 22, height: 22))
    styleButton.image = NSImage(
      systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "颜色与字号")
    styleButton.imagePosition = .imageOnly
    styleButton.isBordered = false
    styleButton.contentTintColor = ink.withAlphaComponent(0.4)
    styleButton.autoresizingMask = [.minYMargin]
    styleButton.target = self
    styleButton.action = #selector(showStyles(_:))
    styleButton.toolTip = "颜色与字号"
    surface.addSubview(styleButton)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func showWindow(_ sender: Any?) {
    guard !expanded else {
      window?.makeKeyAndOrderFront(nil)
      return
    }
    guard let window, let coordinator else { return }
    expanded = true
    window.makeKeyAndOrderFront(nil)
    coordinator.windowAnimator.resize(
      window, to: expandedFrame, duration: 0.28,
      completion: { [weak self] in
        guard let self, !self.collapsing else { return }
        (self.window?.contentView as? PaperSurface)?.allowsDragging = true
        self.textView.resizeImages()
        NSAnimationContext.runAnimationGroup { c in
          c.duration = 0.12
          self.scroll.animator().alphaValue = 1
        }
        self.window?.makeFirstResponder(self.textView)
      })
  }
  func refresh(_ latest: Note) {
    lockButton.isHidden = !latest.pinned
    note.pinned = latest.pinned
    guard !dirty, !saving, !collapsing else { return }
    let contentChanged =
      latest.details != note.details || latest.richContent != note.richContent
      || latest.attachments != note.attachments
    let styleChanged = latest.fontSize != note.fontSize || latest.fontStyle != note.fontStyle
    note = latest
    (window?.contentView as? PaperSurface)?.colorKey = latest.color
    guard contentChanged || styleChanged else { return }
    saving = true
    defer { saving = false }
    let selection = textView.selectedRange()
    let origin = scroll.contentView.bounds.origin
    if contentChanged {
      textView.textStorage?.setAttributedString(NoteDocuments(store: store).detail(latest))
    }
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: latest.fontSize ?? 22, script: latest.fontStyle ?? "xing")
    }
    textView.typingAttributes = summaryStyle(
      latest.fontSize ?? 22, script: latest.fontStyle ?? "xing")
    let length = textView.textStorage?.length ?? 0
    textView.setSelectedRange(
      NSRange(
        location: min(selection.location, length),
        length: min(selection.length, max(0, length - selection.location))))
    textView.resizeImages()
    scroll.contentView.scroll(to: origin)
    scroll.reflectScrolledClipView(scroll.contentView)
  }
  func prepareForRemoval() {
    saveTimer?.invalidate()
    collapsing = true
  }
  override func close() { collapse() }
  func collapse() {
    guard !collapsing, saveDraft(), let w = window, let coordinator else { return }
    (w as? StickyPanel)?.movement.stop()
    (w.contentView as? PaperSurface)?.allowsDragging = false
    collapsing = true
    w.delegate = nil
    NSAnimationContext.runAnimationGroup { c in
      c.duration = 0.08
      scroll.animator().alphaValue = 0
    }
    coordinator.windowAnimator.resize(
      w, to: collapsedFrame, duration: 0.25,
      completion: { [weak self] in
        guard let self, let owner = self.coordinator, owner.details[self.note.id] === self,
          owner.panels[self.note.id] === w
        else { return }
        let latest = (try? self.store.note(self.note.id)) ?? self.note
        w.contentView = PaperView(note: latest, owner: owner)
        w.delegate = owner
        owner.configureLevel(w, pinned: latest.pinned)
        owner.details.removeValue(forKey: self.note.id)
      })
  }
  func settledOrigin(afterMoving frame: NSRect) -> NSPoint {
    collapsedFrame.origin = PaperGlide.containedOrigin(
      NSPoint(
        x: collapsedFrame.minX + frame.minX - expandedFrame.minX,
        y: collapsedFrame.minY + frame.minY - expandedFrame.minY),
      size: collapsedFrame.size, screens: NSScreen.screens.map(\.visibleFrame))
    expandedFrame = frame
    return collapsedFrame.origin
  }
  func textDidChange(_ notification: Notification) {
    guard !saving else { return }
    dirty = true
    guard !textView.hasMarkedText() else { return }
    saving = true
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: note.fontSize ?? 22, script: note.fontStyle ?? "xing")
    }
    textView.typingAttributes = summaryStyle(note.fontSize ?? 22, script: note.fontStyle ?? "xing")
    textView.resizeImages()
    saving = false
    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
      _ = self?.saveDraft()
    }
  }
  func textViewDidChangeSelection(_ notification: Notification) {
    if !saving { textView.scheduleSelectionMenu() }
  }
  func paperMenu() -> NSMenu {
    let m = NSMenu()
    m.addItem(withTitle: "新建便签", action: #selector(AppController.newNote), keyEquivalent: "")
      .target = coordinator
    m.addItem(withTitle: "收起", action: #selector(shrink), keyEquivalent: "").target = self
    m.addItem(.separator())
    let style = m.addItem(withTitle: "颜色与字号", action: nil, keyEquivalent: "")
    let sub = NSMenu()
    sub.autoenablesItems = false
    for (key, name, _) in paperColors {
      let i = sub.addItem(withTitle: name, action: #selector(changeColor(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = key
      i.state = note.color == key ? .on : .off
    }
    sub.addItem(.separator())
    for (name, size) in [("小号 · 18", 18.0), ("中号 · 22", 22.0), ("大号 · 26", 26.0)] {
      let i = sub.addItem(withTitle: name, action: #selector(changeSize(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = size
      i.state = (note.fontSize ?? 22) == size ? .on : .off
    }
    sub.addItem(.separator())
    for (key, name) in paperScripts {
      let i = sub.addItem(withTitle: name, action: #selector(changeScript(_:)), keyEquivalent: "")
      i.target = self
      i.representedObject = key
      i.state = (note.fontStyle ?? "xing") == key ? .on : .off
    }
    style.submenu = sub
    m.addItem(
      withTitle: note.pinned ? "改为桌面小组件" : "浮在窗口上方", action: #selector(changePaperMode),
      keyEquivalent: ""
    ).target = self
    m.addItem(.separator())
    m.addItem(withTitle: "删除便签", action: #selector(removePaper), keyEquivalent: "").target = self
    return m
  }
  @objc func shrink() { collapse() }
  @objc func showStyles(_ sender: NSButton) {
    if let menu = paperMenu().items.first(where: { $0.title == "颜色与字号" })?.submenu {
      menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }
  }
  @objc func changeColor(_ item: NSMenuItem) {
    guard saveDraft(), let key = item.representedObject as? String else { return }
    coordinator?.mutate(note.id) { $0.color = key }
    if let latest = try? store.note(note.id) { note = latest }
    (window?.contentView as? PaperSurface)?.colorKey = key
  }
  @objc func changeSize(_ item: NSMenuItem) {
    guard saveDraft(), let size = item.representedObject as? Double else { return }
    coordinator?.mutate(note.id) { $0.fontSize = size }
    if let latest = try? store.note(note.id) { note = latest }
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: size, script: note.fontStyle ?? "xing")
    }
    textView.typingAttributes = summaryStyle(size, script: note.fontStyle ?? "xing")
    dirty = true
    _ = saveDraft()
  }
  @objc func changeScript(_ item: NSMenuItem) {
    guard saveDraft(), let script = item.representedObject as? String else { return }
    coordinator?.mutate(note.id) { $0.fontStyle = script }
    if let latest = try? store.note(note.id) { note = latest }
    if let storage = textView.textStorage {
      applyPaperTypography(storage, size: note.fontSize ?? 22, script: script)
    }
    textView.typingAttributes = summaryStyle(note.fontSize ?? 22, script: script)
    dirty = true
    _ = saveDraft()
  }
  @objc func changePaperMode() {
    if saveDraft() {
      coordinator?.mutate(note.id) { $0.pinned.toggle() }
      if let latest = try? store.note(note.id) { note = latest }
      collapse()
    }
  }
  @objc func unlockPaper() {
    if saveDraft() { coordinator?.mutate(note.id) { $0.pinned = false } }
  }
  @objc func removePaper() {
    if saveDraft() {
      coordinator?.mutate(note.id) { $0.completed = true }
      coordinator?.details.removeValue(forKey: note.id)
    }
  }
  @discardableResult func saveDraft() -> Bool {
    saveTimer?.invalidate()
    guard dirty, !saving else { return true }
    saving = true
    defer { saving = false }
    do {
      guard let storage = textView.textStorage else { return false }
      note = try NoteDocuments(store: store).saveDetail(base: note, text: storage)
      dirty = false
      coordinator?.reload()
      return true
    } catch {
      showError(error)
      return false
    }
  }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    collapse()
    return false
  }
  func windowDidResignKey(_ notification: Notification) {
    if !saving && !collapsing { _ = saveDraft() }
  }
  func windowWillClose(_ notification: Notification) {
    saveTimer?.invalidate()
    if coordinator?.details[note.id] === self { coordinator?.details.removeValue(forKey: note.id) }
  }
}
