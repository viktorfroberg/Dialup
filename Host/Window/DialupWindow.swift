import AppKit

/// A frameless, transparent window: the skin draws the entire window, including its corners
/// (rounded XP/Aqua tops, square Classic), so macOS's own rounded corner doesn't cut into it.
final class DialupWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .closable, .miniaturizable, .resizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.fullScreenPrimary, .managed]
        isMovableByWindowBackground = false
    }

    /// The latest left mouse-down. Title bar drags start from it: the chrome's `windowDrag` message
    /// arrives asynchronously, when `NSApp.currentEvent` may already be another event.
    private(set) var lastLeftMouseDown: NSEvent?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { lastLeftMouseDown = event }
        super.sendEvent(event)
    }

    // Borderless windows don't become key or main by default.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // There are no native title bar buttons, so the standard perform… actions (which simulate a
    // button click and beep without one) are done directly.
    override func performClose(_ sender: Any?) {
        if delegate?.windowShouldClose?(self) ?? true { close() }
    }
    override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
    override func performZoom(_ sender: Any?) { zoom(sender) }
}
