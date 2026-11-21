import AppKit

/// Content view of a browser window. The chrome web view fills the whole view.
/// The page web view sits on top of it, inset by the margins the chrome reports.
/// Insets (not absolute rects) mean live window resizing never waits on JavaScript.
/// The scanline overlay (extreme mode) covers everything and ignores clicks.
final class BrowserLayoutView: NSView {
    override var isFlipped: Bool { true }

    let scanlineView: ScanlineView = {
        let view = ScanlineView(frame: .zero)
        view.isHidden = true
        return view
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
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

    /// Extreme mode: scanlines over the whole window, or only over the page (default).
    var scanlinesCoverChrome = false {
        didSet { needsLayout = true }
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
    }
}
