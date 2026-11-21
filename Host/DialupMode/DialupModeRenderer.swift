import AppKit
import CoreImage
import WebKit

/// Applies Dial-up Mode settings to one window: Core Image filters (hard mode), the scanline
/// overlay and the in-page script.
@MainActor
enum DialupModeRenderer {
    /// CIDither strength for the dithered web-safe palette: visible grain, still readable.
    private static let ditherIntensity = 0.12
    /// Posterize levels per channel: 32 ≈ 5 bits = 16-bit "High Color"; 6×6×6 = the 216 web-safe colours.
    private static let thousandsLevels = 32.0
    private static let websafeLevels = 6.0

    /// Core Image filters, only for the opt-in hard-mode options (whole-page colours, pixels).
    static func filters(for s: DialupModeSettings, backingScale: CGFloat) -> [CIFilter] {
        guard s.enabled else { return [] }
        var filters: [CIFilter] = []

        let block: CGFloat = switch s.resolution {
        case .retina: 0
        case .classic: backingScale        // one CSS pixel = one screen pixel, like a non-Retina CRT
        case .chunky: backingScale * 2
        }
        if block > 1, let f = CIFilter(name: "CIPixellate") {
            f.setValue(CIVector(x: 0, y: 0), forKey: kCIInputCenterKey)
            f.setValue(block, forKey: kCIInputScaleKey)
            filters.append(f)
        }

        if s.colors == .websafeDither, let f = CIFilter(name: "CIDither") {
            f.setValue(ditherIntensity, forKey: kCIInputIntensityKey)
            filters.append(f)
        }
        let levels: Double? = switch s.colors {
        case .millions, .gifImages: nil
        case .thousands: thousandsLevels
        case .websafe, .websafeDither: websafeLevels
        }
        if let levels, let f = CIFilter(name: "CIColorPosterize") {
            f.setValue(levels, forKey: "inputLevels")
            filters.append(f)
        }
        return filters
    }

    /// `page` is the visible tab (gets the window filters); `allPages` get the page script.
    static func apply(_ s: DialupModeSettings, to layoutView: BrowserLayoutView, page: WKWebView,
                      allPages: [WKWebView], pageScript: DialupModePageScript, skin: Skin) {
        let scale = layoutView.window?.backingScaleFactor ?? 2
        let target: NSView = s.includeChrome ? layoutView : page
        let other: NSView = s.includeChrome ? page : layoutView
        other.contentFilters = []
        target.wantsLayer = true
        target.layerUsesCoreImageFilters = true
        target.contentFilters = filters(for: s, backingScale: scale)
        layoutView.scanlinesCoverChrome = s.includeChrome
        layoutView.scanlineView.isHidden = !(s.enabled && s.scanlines)
        pageScript.apply(s, to: allPages.isEmpty ? [page] : allPages, skin: skin)
    }
}
