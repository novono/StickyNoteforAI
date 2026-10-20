import AppKit

@main struct MotionTests {
  static func main() throws {
    _ = NSApplication.shared
    let samples = (0..<100).map { PaperAppearance(id: "sample-\($0)") }
    precondition(samples == ((0..<100).map { PaperAppearance(id: "sample-\($0)") }))
    precondition(samples.allSatisfy { $0.corner == .lowerRight })
    precondition(Set(samples.map { $0.curlWidth }).count > 90)
    let frame = NSRect(x: 250, y: 250, width: 280, height: 266)
    let owner = AppController()
    let n = try Store.shared.create(Note(summary: "贴上便签\n撕下便签"))
    let panel = StickyPanel(
      contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.identifier = NSUserInterfaceItemIdentifier(n.id)
    let view = PaperView(note: n, owner: owner)
    panel.contentView = view
    panel.delegate = owner
    owner.panels[n.id] = panel
    var completed = 0
    PaperMotion.play(.stick, on: panel) { completed += 1 }
    // A new detail request must be able to finish arrival before accessing the editor.
    PaperMotion.finish(panel)
    precondition(completed == 1 && panel.contentView === view && panel.frame == frame)
    precondition(!PaperMotion.isAnimating(panel))
    precondition((try? Store.shared.note(n.id).x) == nil)
    PaperMotion.play(.stick, on: panel) { completed += 1 }
    let end = Date().addingTimeInterval(1)
    while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(completed == 2 && panel.contentView === view && panel.frame == frame)
    precondition(!PaperMotion.isAnimating(panel))
    precondition((try? Store.shared.note(n.id).x) == nil)
    PaperMotion.play(.tear, on: panel) { completed += 1 }
    let tearEnd = Date().addingTimeInterval(1)
    while Date() < tearEnd { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    precondition(completed == 3 && !panel.isVisible && !PaperMotion.isAnimating(panel))
    print(
      "PASS: arrival, interrupted arrival, original editor/frame restoration, stable stored position, tear completion and cleanup"
    )
  }
}
