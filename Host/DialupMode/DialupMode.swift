import AppKit
import CoreImage
import WebKit

/// Dial-up mode: browse like it's ~2000, and stay usable.
/// The heart of it is the *loading experience*: text appears at once, images trickle in
/// line by line at the simulated connection speed (capped), and the status bar counts down
/// "(n items remaining)". Text is never filtered unless the user opts into the hard-mode
/// whole-page effects. Everything is off and free when disabled.
struct DialupModeSettings: Codable, Equatable {
    enum Connection: String, Codable { case off, dsl, isdn, modem56k }
    /// `gifImages` (default) only touches images; the `page…` options filter the whole page (hard mode).
    enum Colors: String, Codable { case millions, gifImages, thousands, websafe, websafeDither }
    enum Resolution: String, Codable { case retina, classic, chunky }

    var enabled = false
    var connection: Connection = .modem56k
    var colors: Colors = .gifImages
    var resolution: Resolution = .retina
    var scanlines = true
    var oldFonts = false
    /// Off by default: window effects only touch the page, the browser UI stays crisp.
    var includeChrome = false

    init(enabled: Bool = false, connection: Connection = .modem56k, colors: Colors = .gifImages,
         resolution: Resolution = .retina, scanlines: Bool = true, oldFonts: Bool = false, includeChrome: Bool = false) {
        self.enabled = enabled
        self.connection = connection
        self.colors = colors
        self.resolution = resolution
        self.scanlines = scanlines
        self.oldFonts = oldFonts
        self.includeChrome = includeChrome
    }

    static let fallbackKey = CodingUserInfoKey(rawValue: "fallback")!

    /// Tolerant: a missing or unknown value falls back (to `userInfo[fallbackKey]` or defaults),
    /// so settings saved by older versions keep working.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = decoder.userInfo[Self.fallbackKey] as? DialupModeSettings ?? DialupModeSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        enabled = value(.enabled, d.enabled)
        connection = value(.connection, d.connection)
        colors = value(.colors, d.colors)
        resolution = value(.resolution, d.resolution)
        scanlines = value(.scanlines, d.scanlines)
        oldFonts = value(.oldFonts, d.oldFonts)
        includeChrome = value(.includeChrome, d.includeChrome)
    }

    static let presets: [String: DialupModeSettings] = [
        "1998": DialupModeSettings(enabled: true, connection: .modem56k, colors: .gifImages, scanlines: true, oldFonts: true),
        "2003": DialupModeSettings(enabled: true, connection: .dsl, colors: .millions, scanlines: false, oldFonts: false),
    ]

    var dictionary: [String: Any] {
        (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    }

    /// Returns a copy with the given keys replaced; unknown keys and invalid values are ignored.
    func merging(_ patch: [String: Any]) -> DialupModeSettings {
        var dict = dictionary
        for (key, value) in patch where dict[key] != nil { dict[key] = value }
        let decoder = JSONDecoder()
        decoder.userInfo[Self.fallbackKey] = self
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let merged = try? decoder.decode(DialupModeSettings.self, from: data) else { return self }
        return merged
    }

    /// Simulated line speed for image trickle-in; 0 = no throttling.
    var bitsPerSecond: Int {
        guard enabled else { return 0 }
        return switch connection {
        case .off: 0
        case .dsl: 512_000
        case .isdn: 128_000
        case .modem56k: 53_333 // what a "56k" modem actually connected at
        }
    }
}

/// App-wide dial-up mode state, persisted in UserDefaults and broadcast to all windows.
@MainActor
final class DialupMode {
    static let shared = DialupMode()
    static let didChange = Notification.Name("DialupModeDidChange")
    private static let defaultsKey = "DialupModeSettings"

    var settings: DialupModeSettings {
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
           let saved = try? JSONDecoder().decode(DialupModeSettings.self, from: data) {
            settings = saved
        } else {
            settings = DialupModeSettings()
        }
    }
}

/// Applies dial-up mode settings to one window.
@MainActor
enum DialupModeRenderer {
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
            f.setValue(0.12, forKey: kCIInputIntensityKey)
            filters.append(f)
        }
        let levels: Double? = switch s.colors {
        case .millions, .gifImages: nil
        case .thousands: 32                // 5 bits per channel ≈ 16-bit "High Color"
        case .websafe, .websafeDither: 6   // 6×6×6 = the 216 web-safe colours
        }
        if let levels, let f = CIFilter(name: "CIColorPosterize") {
            f.setValue(levels, forKey: "inputLevels")
            filters.append(f)
        }
        return filters
    }

    static func apply(_ s: DialupModeSettings, to layoutView: BrowserLayoutView, page: WKWebView) {
        let scale = layoutView.window?.backingScaleFactor ?? 2
        let target: NSView = s.includeChrome ? layoutView : page
        let other: NSView = s.includeChrome ? page : layoutView
        other.contentFilters = []
        target.wantsLayer = true
        target.layerUsesCoreImageFilters = true
        target.contentFilters = filters(for: s, backingScale: scale)
        layoutView.scanlinesCoverChrome = s.includeChrome
        layoutView.scanlineView.isHidden = !(s.enabled && s.scanlines)
        DialupModePage.apply(s, to: page)
    }
}

/// The in-page part of dial-up mode: image trickle-in, GIF-style image colours, old fonts.
/// Runs in an isolated content world, so page scripts can't see or tamper with it.
/// Reports `{remaining, total, url}` for the status bar.
@MainActor
final class DialupModePage: NSObject, WKScriptMessageHandler {
    static let world = WKContentWorld.world(name: "dialup-mode")
    static let handlerName = "dialupLoading"
    private static let marker = "__dialupMode"

    /// (webView, items remaining, items total, url being "downloaded")
    var onStatus: ((WKWebView, Int, Int, String) -> Void)?

    func install(on controller: WKUserContentController) {
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let webView = message.webView else { return }
        let remaining = max(0, (body["remaining"] as? NSNumber)?.intValue ?? 0)
        let total = max(0, (body["total"] as? NSNumber)?.intValue ?? 0)
        let url = String((body["url"] as? String ?? "").prefix(300))
        onStatus?(webView, remaining, total, url)
    }

    static func config(for s: DialupModeSettings) -> [String: Any] {
        [
            "enabled": s.enabled,
            "bps": s.bitsPerSecond,
            "gifImages": s.enabled && s.colors == .gifImages,
            "oldFonts": s.enabled && s.oldFonts,
        ]
    }

    static func script(for s: DialupModeSettings) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: config(for: s)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return pageScript.replacingOccurrences(of: "__CFG__", with: json)
    }

    static func apply(_ s: DialupModeSettings, to webView: WKWebView) {
        let controller = webView.configuration.userContentController
        let others = controller.userScripts.filter { !$0.source.contains(marker) }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        let source = script(for: s)
        if s.enabled {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: world))
        }
        webView.evaluateJavaScript(source, in: nil, in: world, completionHandler: nil)
    }

    // Kept in one place so it's easy to tweak. `__CFG__` is replaced with the JSON config.
    private static let pageScript = #"""
    (() => {
      const cfg = __CFG__;
      const api = window.__dialupMode || (window.__dialupMode = create());
      api.update(cfg);

      function create() {
        let cfg = {};
        const queue = [];
        const seen = new WeakSet();
        let active = 0, total = 0, currentUrl = '', style = null, svg = null, lastPost = 0, postTimer = null;
        const MAX_PARALLEL = 4;   // browsers of the era opened a few connections at once
        const CSS_HIDE = 'img:not([data-dialup-shown]){visibility:hidden!important}';
        const CSS_GIF = 'img,video{filter:url(#dialup-websafe)}';
        const CSS_FONTS = 'html,body,p,div,td,th,li,dd,dt,a,label,input,textarea,select,button,h1,h2,h3,h4,h5,h6,blockquote{font-family:Verdana,Tahoma,"Times New Roman",serif!important}'
          + 'pre,code,kbd,samp,tt{font-family:"Courier New",Courier,monospace!important}'
          + '*{-webkit-font-smoothing:none!important}';

        const show = (img) => img.setAttribute('data-dialup-shown', '');
        const remaining = () => queue.length + active;

        function post(force) {
          const now = Date.now();
          if (!force && now - lastPost < 120) {
            if (!postTimer) postTimer = setTimeout(() => { postTimer = null; post(true); }, 120);
            return;
          }
          lastPost = now;
          try {
            window.webkit.messageHandlers.dialupLoading.postMessage({ remaining: remaining(), total, url: currentUrl });
          } catch (_) {}
        }

        function attach(node) {
          const parent = document.head || document.documentElement;
          if (parent) parent.appendChild(node);
          else document.addEventListener('readystatechange', () => attach(node), { once: true });
        }

        function ensureSvg() {
          if (svg && svg.isConnected) return;
          if (!document.body) { document.addEventListener('DOMContentLoaded', ensureSvg, { once: true }); return; }
          svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
          svg.setAttribute('width', '0');
          svg.setAttribute('height', '0');
          svg.setAttribute('aria-hidden', 'true');
          svg.style.position = 'absolute';
          const t = 'type="discrete" tableValues="0 .2 .4 .6 .8 1"';
          svg.innerHTML = `<filter id="dialup-websafe" color-interpolation-filters="sRGB"><feComponentTransfer>`
            + `<feFuncR ${t}/><feFuncG ${t}/><feFuncB ${t}/></feComponentTransfer></filter>`;
          document.body.appendChild(svg);
        }

        function bytes(img) {
          const src = img.currentSrc || img.src;
          const entry = performance.getEntriesByName(src)[0];
          const size = entry && (entry.encodedBodySize || entry.transferSize);
          return size > 0 ? size : Math.max(2000, img.naturalWidth * img.naturalHeight * 0.3);
        }

        function pump() {
          while (active < MAX_PARALLEL && queue.length) {
            const img = queue.shift();
            if (!img.isConnected) continue;
            active++;
            currentUrl = img.currentSrc || img.src;
            // Real speed, but capped, and the cap shrinks as the backlog grows: fun, not annoying.
            const cap = Math.max(300, 2500 - queue.length * 100);
            const ms = Math.min(cap, Math.max(150, bytes(img) * 8 / cfg.bps * 1000));
            const base = cfg.gifImages ? 'url(#dialup-websafe) ' : '';
            show(img);
            const anim = img.animate([
              { clipPath: 'inset(0 0 100% 0)', filter: base + 'blur(3px)' },
              { clipPath: 'inset(0 0 0 0)', filter: base + 'blur(0px)' },
            ], { duration: ms, easing: `steps(${Math.max(4, Math.round(ms / 50))}, end)` });
            // A timer drives the queue (WebKit pauses animations in hidden windows);
            // the animation is just the look.
            let finished = false;
            const finish = () => {
              if (finished) return;
              finished = true;
              try { anim.finish(); } catch (_) {}
              active--;
              pump();
            };
            anim.onfinish = finish;
            anim.oncancel = finish;
            setTimeout(finish, ms + 50);
          }
          post(remaining() === 0);
        }

        function schedule(img) {
          if (seen.has(img)) return;
          seen.add(img);
          if (!cfg.enabled || !cfg.bps || img.naturalWidth * img.naturalHeight <= 4) { show(img); return; }
          total++;
          queue.push(img);
          pump();
        }

        document.addEventListener('load', (e) => { if (e.target instanceof HTMLImageElement) schedule(e.target); }, true);
        document.addEventListener('error', (e) => { if (e.target instanceof HTMLImageElement) show(e.target); }, true);

        return {
          update(next) {
            cfg = next;
            if (!cfg.enabled) {
              if (style) style.remove();
              if (svg) svg.remove();
              queue.splice(0).forEach(show);
              post(true);
              return;
            }
            if (!style) { style = document.createElement('style'); style.id = 'dialup-mode-style'; }
            style.textContent = (cfg.bps ? CSS_HIDE : '') + (cfg.gifImages ? CSS_GIF : '') + (cfg.oldFonts ? CSS_FONTS : '');
            if (!style.isConnected) attach(style);
            if (cfg.gifImages) ensureSvg();
            // Turned on mid-page: don't re-hide what's already loaded; the next page trickles in.
            document.querySelectorAll('img').forEach((img) => { if (img.complete) { seen.add(img); show(img); } });
            if (!cfg.bps) queue.splice(0).forEach(show);
          },
        };
      }
    })();
    """#
}

/// CRT scanlines + a soft vignette over the page. Deliberately faint. Ignores all clicks.
final class ScanlineView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let stripe = NSImage(size: NSSize(width: 1, height: 3), flipped: false) { _ in
            NSColor.black.withAlphaComponent(0.045).setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            return true
        }
        layer?.backgroundColor = NSColor(patternImage: stripe).cgColor
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.08).cgColor]
        vignette.locations = [0.7, 1]
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
