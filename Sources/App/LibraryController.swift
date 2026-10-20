import AppKit

final class LibraryController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate,
  NSSearchFieldDelegate
{
  weak var coordinator: AppController?
  var notes: [Note] = []
  let table = NSTableView()
  let search = NSSearchField()
  let filter = NSPopUpButton()
  init(owner: AppController) {
    self.coordinator = owner
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    w.title = "所有便签"
    w.isReleasedWhenClosed = false
    w.center()
    super.init(window: w)
    let c = w.contentView!
    search.frame = NSRect(x: 20, y: 426, width: 454, height: 30)
    search.placeholderString = "找一句话、详情或来源"
    search.delegate = self
    c.addSubview(search)
    filter.frame = NSRect(x: 486, y: 426, width: 154, height: 30)
    filter.addItems(withTitles: ["桌面上的", "已收起", "全部"])
    filter.target = self
    filter.action = #selector(refresh)
    c.addSubview(filter)
    let scroll = NSScrollView(frame: NSRect(x: 20, y: 65, width: 620, height: 345))
    scroll.hasVerticalScroller = true
    let title = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("summary"))
    title.title = "便签"
    title.width = 420
    table.addTableColumn(title)
    let source = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
    source.title = "分类 · 来源"
    source.width = 170
    table.addTableColumn(source)
    table.rowHeight = 46
    table.dataSource = self
    table.delegate = self
    table.doubleAction = #selector(openSelected)
    table.target = self
    scroll.documentView = table
    c.addSubview(scroll)
    c.addSubview(
      button(
        "新便签", frame: NSRect(x: 16, y: 18, width: 100, height: 32), target: owner,
        action: #selector(AppController.newNote)))
    refresh()
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc func refresh() {
    do {
      let q = search.stringValue.lowercased()
      notes = try (coordinator?.store ?? .shared).all().filter { n in
        (filter.indexOfSelectedItem == 2 || n.completed == (filter.indexOfSelectedItem == 1))
          && (q.isEmpty
            || "\(n.summary) \(n.details) \(n.sourceName) \(n.category)".lowercased().contains(q))
      }.sorted {
        $0.category == $1.category ? $0.updatedAt > $1.updatedAt : $0.category < $1.category
      }
      table.reloadData()
    } catch { showError(error) }
  }
  func controlTextDidChange(_ obj: Notification) { refresh() }
  func numberOfRows(in tableView: NSTableView) -> Int { notes.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let n = notes[row]
    let v = NSTextField(
      labelWithString: tableColumn?.identifier.rawValue == "summary"
        ? (n.completed ? "✓  " : "") + n.summary.replacingOccurrences(of: "\n", with: " · ")
        : n.category + " · " + n.sourceName)
    v.lineBreakMode = .byTruncatingTail
    v.font = .systemFont(ofSize: 13)
    return v
  }
  @objc func openSelected() {
    let row = table.clickedRow
    if row >= 0, row < notes.count { coordinator?.edit(notes[row].id) }
  }
}
