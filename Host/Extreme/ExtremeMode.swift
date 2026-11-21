import AppKit
import CoreImage
import WebKit

/// Extreme mode makes browsing look and feel like ~2000.
/// Rule: effects work on the finished image of the window (Core Image filters, an overlay
/// that ignores clicks) or, later, on the network. Pages aren't rewritten, except the
/// opt-in "old fonts" style sheet. Everything is off and free when disabled.
struct ExtremeSettings: Codable, Equatable {
    enum Colors: String, Codable { case millions, thousands, websafe, websafeDither }
    enum Resolution: String, Codable { case retina, classic, chunky }

    var enabled = false
    var colors: Colors = .websafeDither
    var resolution: Resolution = .classic
    var scanlines = true
    var oldFonts = false
    /// Off by default: effects only touch the page, the browser UI stays crisp.
    var includeChrome = false

    init(enabled: Bool = false, colors: Colors = .websafeDither, resolution: Resolution = .classic,
         scanlines: Bool = true, oldFonts: Bool = false, includeChrome: Bool = false) {
        self.enabled = enabled
        self.colors = colors
        self.resolution = resolution
        self.scanlines = scanlines
        self.oldFonts = oldFonts
        self.includeChrome = includeChrome
    }

    /// Tolerates missing keys so settings saved by older versions keep working.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExtremeSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        colors = try c.decodeIfPresent(Colors.self, forKey: .colors) ?? d.colors
        resolution = try c.decodeIfPresent(Resolution.self, forKey: .resolution) ?? d.resolution
        scanlines = try c.decodeIfPresent(Bool.self, forKey: .scanlines) ?? d.scanlines
        oldFonts = try c.decodeIfPresent(Bool.self, forKey: .oldFonts) ?? d.oldFonts
        includeChrome = try c.decodeIfPresent(Bool.self, forKey: .includeChrome) ?? d.includeChrome
    }

    static let presets: [String: ExtremeSettings] = [
        "1998": ExtremeSettings(enabled: true, colors: .websafeDither, resolution: .classic, scanlines: true, oldFonts: true),
        "2003": ExtremeSettings(enabled: true, colors: .thousands, resolution: .classic, scanlines: false, oldFonts: false),
    ]

    var dictionary: [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }

    /// Returns a copy with the given keys replaced; unknown keys/values are ignored.
    func merging(_ patch: [String: Any]) -> ExtremeSettings {
        var dict = dictionary
        for (key, value) in patch where dict[key] != nil { dict[key] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let merged = try? JSONDecoder().decode(ExtremeSettings.self, from: data) else { return self }
        return merged
    }
}

/// App-wide extreme mode state, persisted in UserDefaults and broadcast to all windows.
@MainActor
final class ExtremeMode {
    static let shared = ExtremeMode()
    static let didChange = Notification.Name("DialupExtremeModeDidChange")
    private static let defaultsKey = "ExtremeSettings"

    var settings: ExtremeSettings {
        didSet {
            guard settings != oldValue else { return }
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(ExtremeSettings.self, from: data) {
            settings = saved
        } else {
            settings = ExtremeSettings()
        }
    }
}

/// Applies extreme settings to one window.
@MainActor
enum ExtremeRenderer {
    /// Core Image filters for the page (or, with includeChrome, the whole window).
    static func filters(for s: ExtremeSettings, backingScale: CGFloat) -> [CIFilter] {
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
            f.setValue(0.12, forKey: kCIInputIntensityKey)
            filters.append(f)
        }
        let levels: Double? = switch s.colors {
        case .millions: nil
        case .thousands: 32                // 5 bits per channel ≈ 16-bit "High Color"
        case .websafe, .websafeDither: 6   // 6×6×6 = the 216 web-safe colours
        }
        if let levels, let f = CIFilter(name: "CIColorPosterize") {
            f.setValue(levels, forKey: "inputLevels")
            filters.append(f)
        }
        return filters
    }

    static func apply(_ s: ExtremeSettings, to layoutView: BrowserLayoutView, page: WKWebView) {
        let scale = layoutView.window?.backingScaleFactor ?? 2
        let target: NSView = s.includeChrome ? layoutView : page
        let other: NSView = s.includeChrome ? page : layoutView
        other.contentFilters = []
        target.wantsLayer = true
        target.layerUsesCoreImageFilters = true
        target.contentFilters = filters(for: s, backingScale: scale)
        layoutView.scanlinesCoverChrome = s.includeChrome
        layoutView.scanlineView.isHidden = !(s.enabled && s.scanlines)
        OldFonts.apply(s.enabled && s.oldFonts, to: page)
    }
}

/// Opt-in period fonts with font smoothing off. Injected from an isolated content world.
@MainActor
enum OldFonts {
    static let world = WKContentWorld.world(name: "dialup-extreme")
    static let css = """
    html, body, p, div, td, th, li, dd, dt, a, label, input, textarea, select, button, h1, h2, h3, h4, h5, h6, blockquote, pre, code {
      font-family: Verdana, Tahoma, "Times New Roman", serif !important;
    }
    pre, code, kbd, samp, tt { font-family: "Courier New", Courier, monospace !important; }
    * { -webkit-font-smoothing: none !important; text-rendering: optimizeSpeed !important; }
    """

    static func script(enabled: Bool) -> String {
        let cssLiteral = (try? String(data: JSONSerialization.data(withJSONObject: [css]), encoding: .utf8)) ?? "[\"\"]"
        return """
        (() => {
          const id = 'dialup-old-fonts';
          let el = document.getElementById(id);
          if (\(enabled)) {
            if (!el) {
              el = document.createElement('style');
              el.id = id;
              el.textContent = \(cssLiteral)[0];
              (document.head || document.documentElement).appendChild(el);
            }
          } else if (el) {
            el.remove();
          }
        })();
        """
    }

    static func apply(_ enabled: Bool, to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        let existing = controller.userScripts.filter { !$0.source.contains("dialup-old-fonts") }
        controller.removeAllUserScripts()
        existing.forEach(controller.addUserScript)
        if enabled {
            controller.addUserScript(WKUserScript(source: script(enabled: true), injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: world))
        }
        webView.evaluateJavaScript(script(enabled: enabled), in: nil, in: world, completionHandler: nil)
    }
}

/// CRT scanlines + a soft vignette, drawn above the window content. Ignores all clicks.
final class ScanlineView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let stripe = NSImage(size: NSSize(width: 1, height: 3), flipped: false) { _ in
            NSColor.black.withAlphaComponent(0.09).setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            return true
        }
        layer?.backgroundColor = NSColor(patternImage: stripe).cgColor
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.14).cgColor]
        vignette.locations = [0.65, 1]
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
