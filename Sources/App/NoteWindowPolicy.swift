import AppKit

/// Desktop paper is below ordinary app windows, but above Finder and wallpaper
/// surfaces. Avoid the special desktop-icon level: WindowManager can conceal
/// third-party panels in that group when revealing the desktop.
enum NoteWindowPolicy {
  static let desktopLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)

  static func apply(to window: NSWindow, pinned: Bool) {
    let oldLevel = window.level
    if let panel = window as? NSPanel {
      panel.isFloatingPanel = pinned
      panel.hidesOnDeactivate = false
    }
    window.canHide = false
    window.isExcludedFromWindowsMenu = true
    window.tabbingMode = .disallowed
    window.collectionBehavior =
      pinned
      ? [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
      : [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    window.level = pinned ? .floating : desktopLevel
    if !pinned && oldLevel != window.level && window.isKeyWindow {
      window.resignKey()
    }
    if window.isVisible && oldLevel != window.level { window.orderFrontRegardless() }
  }
}
