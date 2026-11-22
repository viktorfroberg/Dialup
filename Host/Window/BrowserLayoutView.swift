import AppKit

/// Content view of a browser window. The chrome web view fills the whole view.
/// The page web view sits on top of it, inset by the margins the chrome reports.
/// Insets (not absolute rects) mean live window resizing never waits on JavaScript.
/// The scanline overlay (dial-up mode) covers everything and ignores clicks.
final class BrowserLayoutView: NSView {
    override var isFlipped: Bool { true }

    let scanlineView: ScanlineView = {
        let view = ScanlineView(frame: .zero)
        view.isHidden = true
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor // window corners are drawn by the skin
        addSubview(scanlineView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var chromeView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let chromeView { addSubview(chromeView, positioned: .below, relativeTo: nil) }
            needsLayout = true
        }
    }

    var pageView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let pageView { addSubview(pageView, positioned: .below, relativeTo: scanlineView) }
            needsLayout = true
        }
    }

    /// While a retro menu or dialog is open, the (transparent) chrome is raised above the page.
    var chromeOnTop = false {
        didSet {
            guard chromeOnTop != oldValue, let chromeView, let pageView else { return }
            // Reorder in place (assigning `subviews` doesn't remove/re-add, so no flicker or focus loss).
            subviews = chromeOnTop ? [pageView, chromeView, scanlineView] : [chromeView, pageView, scanlineView]
        }
    }

    /// Dial-up mode: scanlines over the whole window, or only over the page (default).
    var scanlinesCoverChrome = false {
        didSet { needsLayout = true }
    }

    /// Called when the pointer moves onto the page. The page covers the chrome there, so the chrome
    /// would never hear that the mouse left its tab or button (and a pending tooltip would show).
    var onPointerEnteredPage: (() -> Void)?
    private var pageTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pageTracking { removeTrackingArea(pageTracking) }
        pageTracking = nil
        guard let pageView, !pageView.isHidden else { return }
        let area = NSTrackingArea(rect: pageView.frame, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        pageTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === pageTracking, !chromeOnTop { onPointerEnteredPage?() }
    }

    /// nil until the chrome has reported its layout; the page stays hidden until then.
    var insets: NSEdgeInsets? {
        didSet { needsLayout = true }
    }

    override func layout() {
        super.layout()
        chromeView?.frame = bounds
        defer { scanlineView.frame = scanlinesCoverChrome ? bounds : (pageView?.frame ?? .zero) }
        guard let pageView else { return }
        guard let i = insets else {
            pageView.isHidden = true
            return
        }
        pageView.isHidden = false
        pageView.frame = NSRect(
            x: i.left,
            y: i.top,
            width: max(0, bounds.width - i.left - i.right),
            height: max(0, bounds.height - i.top - i.bottom)
        )
        updateTrackingAreas()
    }
}
