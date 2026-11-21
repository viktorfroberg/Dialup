import AppKit

/// Dial-up Mode's CRT look: faint scanlines plus a soft vignette over the page.
/// Deliberately subtle, and it ignores all clicks.
final class ScanlineView: NSView {
    /// One dark line every `period` points.
    private static let period: CGFloat = 3
    private static let lineAlpha: CGFloat = 0.045
    private static let vignetteAlpha: CGFloat = 0.08
    /// Where the vignette starts darkening, as a fraction of the radius.
    private static let vignetteStart: NSNumber = 0.7

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let stripe = NSImage(size: NSSize(width: 1, height: Self.period), flipped: false) { _ in
            NSColor.black.withAlphaComponent(Self.lineAlpha).setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            return true
        }
        layer?.backgroundColor = NSColor(patternImage: stripe).cgColor
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(Self.vignetteAlpha).cgColor]
        vignette.locations = [Self.vignetteStart, 1]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        vignette.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        vignette.frame = bounds
        layer?.addSublayer(vignette)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
