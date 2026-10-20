import AppKit
import QuartzCore

final class PaperTextView: NSTextView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  var closeEditor: (() -> Void)?
  var contextMenu: (() -> NSMenu)?
  var plainOnly = false
  var selectionTimer: Timer?
  var selectionPopover: NSPopover?
  override func cancelOperation(_ sender: Any?) { closeEditor?() }
  override func menu(for event: NSEvent) -> NSMenu? {
    let m = contextMenu?() ?? super.menu(for: event) ?? NSMenu()
    if selectedRange().length > 0 {
      let strike = NSMenuItem(
        title: selectionHasStrike() ? "取消划线" : "划掉", action: #selector(toggleStrike),
        keyEquivalent: "")
      strike.target = self
      m.insertItem(.separator(), at: 0)
      m.insertItem(strike, at: 0)
    }
    return m
  }
  func selectionHasStrike() -> Bool {
    let range = selectedRange()
    guard range.length > 0, range.location < (textStorage?.length ?? 0) else { return false }
    return
      (textStorage?.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil)
      as? NSNumber)?.intValue != 0
      && textStorage?.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) != nil
  }
  func scheduleSelectionMenu() {
    selectionTimer?.invalidate()
    if selectedRange().length == 0 {
      selectionPopover?.close()
      return
    }
    selectionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
      self?.showSelectionMenu()
    }
  }
  func showSelectionMenu() {
    guard selectedRange().length > 0, window?.firstResponder === self,
      selectionPopover?.isShown != true, let window
    else { return }
    let controller = NSViewController()
    let button = NSButton(
      title: selectionHasStrike() ? "取消划线" : "划掉", target: self, action: #selector(toggleStrike))
    button.bezelStyle = .rounded
    controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 88, height: 36))
    button.frame = NSRect(x: 5, y: 3, width: 78, height: 30)
    controller.view.addSubview(button)
    let pop = NSPopover()
    pop.contentViewController = controller
    pop.behavior = .semitransient
    pop.animates = true
    let screen = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
    let local = convert(window.convertFromScreen(screen), from: nil)
    selectionPopover = pop
    pop.show(relativeTo: local, of: self, preferredEdge: .maxY)
  }
  @objc func toggleStrike() {
    let range = selectedRange()
    guard range.length > 0, let storage = textStorage, NSMaxRange(range) <= storage.length else {
      return
    }
    let previous = storage.attributedSubstring(from: range)
    undoManager?.registerUndo(withTarget: self) { target in
      target.textStorage?.replaceCharacters(in: range, with: previous)
      target.didChangeText()
    }
    let value = selectionHasStrike() ? 0 : NSUnderlineStyle.single.rawValue
    storage.addAttribute(.strikethroughStyle, value: value, range: range)
    selectionPopover?.close()
    didChangeText()
  }
  override func paste(_ sender: Any?) {
    if plainOnly {
      if let text = NSPasteboard.general.string(forType: .string) {
        insertText(text, replacementRange: selectedRange())
      }
    } else {
      super.paste(sender)
    }
    resizeImages()
  }
  func resizeImages() {
    guard let storage = textStorage else { return }
    var attachments: [NSTextAttachment] = []
    storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
      value, _, _ in if let a = value as? NSTextAttachment { attachments.append(a) }
    }
    for a in attachments {
      if let cell = a.attachmentCell as? NSTextAttachmentCell, let source = cell.image,
        let image = source.copy() as? NSImage
      {
        let maxWidth = max(100, bounds.width - 40)
        if image.size.width > maxWidth {
          image.size = NSSize(
            width: maxWidth, height: image.size.height * maxWidth / image.size.width)
          cell.image = image
        }
      }
    }
  }
}
