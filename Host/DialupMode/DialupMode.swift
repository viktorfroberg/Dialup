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
    var colors: Colors = .millions
    var resolution: Resolution = .retina
    var scanlines = true
    var oldFonts = false
    /// Off by default: window effects only touch the page, the browser UI stays crisp.
    var includeChrome = false

    // Page touches (CSS injected into pages). Safe ones default on; riskier ones are opt-in.
    /// Classic scrollbars, light mode, dotted focus, retro selection, no smooth scroll, no text shadows.
    var retroPage = true
    var squareCorners = true
    var noShadows = false
    var noAnimations = false
    var underlineLinks = false

    init(enabled: Bool = false, connection: Connection = .modem56k, colors: Colors = .millions,
         resolution: Resolution = .retina, scanlines: Bool = true, oldFonts: Bool = false, includeChrome: Bool = false,
         retroPage: Bool = true, squareCorners: Bool = true, noShadows: Bool = false,
         noAnimations: Bool = false, underlineLinks: Bool = false) {
        self.enabled = enabled
        self.connection = connection
        self.colors = colors
        self.resolution = resolution
        self.scanlines = scanlines
        self.oldFonts = oldFonts
        self.includeChrome = includeChrome
        self.retroPage = retroPage
        self.squareCorners = squareCorners
        self.noShadows = noShadows
        self.noAnimations = noAnimations
        self.underlineLinks = underlineLinks
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
        retroPage = value(.retroPage, d.retroPage)
        squareCorners = value(.squareCorners, d.squareCorners)
        noShadows = value(.noShadows, d.noShadows)
        noAnimations = value(.noAnimations, d.noAnimations)
        underlineLinks = value(.underlineLinks, d.underlineLinks)
    }

    static let presets: [String: DialupModeSettings] = [
        "1998": DialupModeSettings(enabled: true, connection: .modem56k, colors: .gifImages, scanlines: true, oldFonts: true,
                                   noShadows: true, underlineLinks: true),
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
            // The dial-in moment: a modem handshake for dial-up speeds, silence for broadband.
            if settings.enabled && !oldValue.enabled && [.modem56k, .isdn].contains(settings.connection) {
                SoundEffects.shared.play(.modem)
            } else if !settings.enabled && oldValue.enabled {
                SoundEffects.shared.stopModem()
            }
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

    /// `page` is the visible tab (gets the window filters); `allPages` get the page script.
    static func apply(_ s: DialupModeSettings, to layoutView: BrowserLayoutView, page: WKWebView,
                      allPages: [WKWebView], pageScripts: DialupModePage) {
        let scale = layoutView.window?.backingScaleFactor ?? 2
        let target: NSView = s.includeChrome ? layoutView : page
        let other: NSView = s.includeChrome ? page : layoutView
        other.contentFilters = []
        target.wantsLayer = true
        target.layerUsesCoreImageFilters = true
        target.contentFilters = filters(for: s, backingScale: scale)
        layoutView.scanlinesCoverChrome = s.includeChrome
        layoutView.scanlineView.isHidden = !(s.enabled && s.scanlines)
        pageScripts.apply(s, to: allPages.isEmpty ? [page] : allPages, skin: PreferencesStore.shared.preferences.skin)
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

    /// Max time one picture takes to trickle in (shared with the settings preview via the catalog).
    nonisolated static let pictureCapMs = 2500

    static func config(for s: DialupModeSettings, skin: String = "luna") -> [String: Any] {
        [
            "capMs": pictureCapMs,
            "enabled": s.enabled,
            "bps": s.bitsPerSecond,
            "gifImages": s.enabled && s.colors == .gifImages,
            "oldFonts": s.enabled && s.oldFonts,
            "retroPage": s.enabled && s.retroPage,
            "squareCorners": s.enabled && s.squareCorners,
            "noShadows": s.enabled && s.noShadows,
            "noAnimations": s.enabled && s.noAnimations,
            "underlineLinks": s.enabled && s.underlineLinks,
            "skin": skin,
        ]
    }

    static func script(for s: DialupModeSettings, skin: String = "luna") -> String {
        let json = (try? JSONSerialization.data(withJSONObject: config(for: s, skin: skin)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return pageScript.replacingOccurrences(of: "__CFG__", with: json)
    }

    private var lastSource: String?

    /// Installs (and live-applies) the page script. No-op when nothing relevant changed, so
    /// unrelated preference or backing-scale changes don't reinstall scripts or reset a trickle.
    /// Note: live updates reach the main frame; iframes pick up changes on their next load.
    func apply(_ s: DialupModeSettings, to webViews: [WKWebView], skin: String) {
        guard let first = webViews.first else { return }
        // No dark mode in 2003: pages render in light appearance while retro page touches are on.
        for webView in webViews { webView.appearance = (s.enabled && s.retroPage) ? NSAppearance(named: .aqua) : nil }
        let source = Self.script(for: s, skin: skin)
        guard source != lastSource else { return }
        let wasInstalled = lastSource != nil
        lastSource = source
        // All tabs of a window share one configuration, so one user content controller.
        let controller = first.configuration.userContentController
        let others = controller.userScripts.filter { !$0.source.contains(Self.marker) }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        if !s.enabled && !wasInstalled { return } // never enabled: nothing to undo on the page
        if s.enabled {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: Self.world))
        }
        for webView in webViews {
            webView.evaluateJavaScript(source, in: nil, in: Self.world, completionHandler: nil)
        }
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
        const CSS_GIF = 'img{filter:url(#dialup-websafe)}';
        const CSS_FONTS = 'html,body,p,div,td,th,li,dd,dt,a,label,input,textarea,select,button,h1,h2,h3,h4,h5,h6,blockquote{font-family:Verdana,Tahoma,"Times New Roman",serif!important}'
          + 'pre,code,kbd,samp,tt{font-family:"Courier New",Courier,monospace!important}'
          + '*{-webkit-font-smoothing:none!important}';

        // Page touches. Safe set first; the rest are opt-in because they can change layouts.
        const svgArrow = (d) => `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='8' height='8'%3E%3Cpath d='${d}' fill='%234d6185'/%3E%3C/svg%3E")`;
        const SCROLLBARS = {
          // XP: light track, blue rounded thumb with a grip, blue arrow buttons at both ends.
          // WebKit only draws buttons whose position is declared (start:decrement / end:increment).
          luna: '::-webkit-scrollbar{width:17px!important;height:17px!important;background:#fdfdfa!important}'
            + '::-webkit-scrollbar-track{background:linear-gradient(90deg,#f3f1ec,#fefefe 40%,#f7f6f2)!important;box-shadow:none!important}'
            + '::-webkit-scrollbar-track:horizontal{background:linear-gradient(#f3f1ec,#fefefe 40%,#f7f6f2)!important}'
            + '::-webkit-scrollbar-thumb{border:1px solid #6d8be0!important;border-radius:3px!important;box-shadow:inset 1px 1px 0 #f0f5ff,inset -1px -1px 0 #9cb3ee!important}'
            + '::-webkit-scrollbar-thumb:vertical{background:repeating-linear-gradient(#f0f5ff 0 1px,#7f9de8 1px 2px) center/7px 8px no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8 55%,#9db6f5)!important}'
            + '::-webkit-scrollbar-thumb:horizontal{background:repeating-linear-gradient(90deg,#f0f5ff 0 1px,#7f9de8 1px 2px) center/8px 7px no-repeat,linear-gradient(#bdd0fb,#a7bff8 55%,#9db6f5)!important}'
            + '::-webkit-scrollbar-thumb:hover{filter:brightness(1.06)!important}'
            + '::-webkit-scrollbar-thumb:active{filter:brightness(.94)!important}'
            + '::-webkit-scrollbar-button{display:none!important}'
            + '::-webkit-scrollbar-button:vertical:start:decrement,::-webkit-scrollbar-button:vertical:end:increment,'
            + '::-webkit-scrollbar-button:horizontal:start:decrement,::-webkit-scrollbar-button:horizontal:end:increment'
            + '{display:block!important;width:17px!important;height:17px!important;border:1px solid #6d8be0!important;border-radius:3px!important;'
            + 'box-shadow:inset 1px 1px 0 #f0f5ff,inset -1px -1px 0 #9cb3ee!important;background-repeat:no-repeat!important;background-position:center!important}'
            + `::-webkit-scrollbar-button:vertical:start:decrement{background:${svgArrow('M0 6 4 2 8 6z')} center no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8)!important}`
            + `::-webkit-scrollbar-button:vertical:end:increment{background:${svgArrow('M0 2 4 6 8 2z')} center no-repeat,linear-gradient(90deg,#bdd0fb,#a7bff8)!important}`
            + `::-webkit-scrollbar-button:horizontal:start:decrement{background:${svgArrow('M6 0 2 4 6 8z')} center no-repeat,linear-gradient(#bdd0fb,#a7bff8)!important}`
            + `::-webkit-scrollbar-button:horizontal:end:increment{background:${svgArrow('M2 0 6 4 2 8z')} center no-repeat,linear-gradient(#bdd0fb,#a7bff8)!important}`
            + '::-webkit-scrollbar-corner{background:#f3f1ec!important}',
          // Windows 98/2000: grey 3D buttons and thumb, dithered track.
          classic: '::-webkit-scrollbar{width:16px!important;height:16px!important;background:#d4d0c8!important}'
            + '::-webkit-scrollbar-track{background:repeating-conic-gradient(#d4d0c8 0 25%,#fff 0 50%) 0 0/2px 2px!important;box-shadow:none!important}'
            + '::-webkit-scrollbar-thumb{background:#d4d0c8!important;border:1px solid!important;border-color:#dfdfdf #404040 #404040 #dfdfdf!important;border-radius:0!important;box-shadow:inset 1px 1px 0 #fff,inset -1px -1px 0 #808080!important}'
            + '::-webkit-scrollbar-button{display:none!important}'
            + '::-webkit-scrollbar-button:vertical:start:decrement,::-webkit-scrollbar-button:vertical:end:increment,'
            + '::-webkit-scrollbar-button:horizontal:start:decrement,::-webkit-scrollbar-button:horizontal:end:increment'
            + '{display:block!important;width:16px!important;height:16px!important;border:1px solid!important;border-color:#dfdfdf #404040 #404040 #dfdfdf!important;border-radius:0!important;box-shadow:inset 1px 1px 0 #fff,inset -1px -1px 0 #808080!important}'
            + `::-webkit-scrollbar-button:vertical:start:decrement{background:${svgArrow('M0 6 4 2 8 6z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
            + `::-webkit-scrollbar-button:vertical:end:increment{background:${svgArrow('M0 2 4 6 8 2z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
            + `::-webkit-scrollbar-button:horizontal:start:decrement{background:${svgArrow('M6 0 2 4 6 8z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
            + `::-webkit-scrollbar-button:horizontal:end:increment{background:${svgArrow('M2 0 6 4 2 8z').replace('%234d6185','%23000')} center no-repeat,#d4d0c8!important}`
            + '::-webkit-scrollbar-button:active{border-color:#808080!important;box-shadow:none!important}'
            + '::-webkit-scrollbar-corner{background:#d4d0c8!important}',
          aqua: '::-webkit-scrollbar{width:15px!important;height:15px!important;background:#ececec!important}'
            + '::-webkit-scrollbar-track{background:linear-gradient(90deg,#cfcfcf,#f2f2f2 40%,#fbfbfb)!important;box-shadow:inset 1px 0 2px rgba(0,0,0,.25)!important}'
            + '::-webkit-scrollbar-track:horizontal{background:linear-gradient(#cfcfcf,#f2f2f2 40%,#fbfbfb)!important}'
            + '::-webkit-scrollbar-thumb{background:linear-gradient(90deg,#3f84ea,#a6d4ff 30%,#5ea6ff 55%,#2f74e0)!important;border:1px solid #2a5fa8!important;border-radius:8px!important}'
            + '::-webkit-scrollbar-thumb:horizontal{background:linear-gradient(#3f84ea,#a6d4ff 30%,#5ea6ff 55%,#2f74e0)!important}'
            + '::-webkit-scrollbar-button:start{display:none!important}'
            + '::-webkit-scrollbar-button:end{display:block!important;width:15px!important;height:15px!important;background:linear-gradient(90deg,#e8e8e8,#fafafa)!important;border:1px solid #b0b0b0!important;background-repeat:no-repeat!important;background-position:center!important}'
            + `::-webkit-scrollbar-button:vertical:end:decrement{background-image:${svgArrow('M0 6 4 2 8 6z')},linear-gradient(90deg,#e8e8e8,#fafafa)!important}`
            + `::-webkit-scrollbar-button:vertical:end:increment{background-image:${svgArrow('M0 2 4 6 8 2z')},linear-gradient(90deg,#e8e8e8,#fafafa)!important}`
            + `::-webkit-scrollbar-button:horizontal:end:decrement{background-image:${svgArrow('M6 0 2 4 6 8z')},linear-gradient(#e8e8e8,#fafafa)!important}`
            + `::-webkit-scrollbar-button:horizontal:end:increment{background-image:${svgArrow('M2 0 6 4 2 8z')},linear-gradient(#e8e8e8,#fafafa)!important}`
            + '::-webkit-scrollbar-corner{background:#ececec!important}',
        };
        const CSS_RETRO = (skin) => '*{scrollbar-color:auto!important;scrollbar-width:auto!important;text-shadow:none!important}'
          + 'html{scroll-behavior:auto!important}'
          + '::selection{background:#316ac5!important;color:#fff!important}'
          + ':focus-visible{outline:1px dotted currentColor!important;outline-offset:1px!important}'
          + (SCROLLBARS[skin] || SCROLLBARS.luna);
        const CSS_SQUARE = '*,*::before,*::after{border-radius:0!important}';
        const CSS_NO_SHADOWS = '*,*::before,*::after{box-shadow:none!important}';
        // 0.01ms, not 0: with 0 no transitionend/animationend fires and some sites wait forever.
        const CSS_NO_MOTION = '*,*::before,*::after{transition-duration:.01ms!important;transition-delay:0s!important;animation-duration:.01ms!important;animation-delay:0s!important;animation-iteration-count:1!important}';
        const CSS_LINKS = 'a[href]{text-decoration:underline!important}';

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
          // Real GIFs chose their 256 colours per picture, so photos kept most of their tones.
          // 10 levels per channel gives that look; the strict web-safe 216 is a separate "hard" option.
          const t = 'type="discrete" tableValues="0 .111 .222 .333 .444 .556 .667 .778 .889 1"';
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
            if (!img.isConnected) { show(img); continue; }
            active++;
            currentUrl = img.currentSrc || img.src;
            // Real speed, but capped, and the cap shrinks as the backlog grows: fun, not annoying.
            const cap = Math.max(300, (cfg.capMs || 2500) - queue.length * 100);
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

        // Images loaded while detached (new Image(), lightboxes, lazy loaders, clones) never fire a
        // load event the document can see, so catch them when they're inserted.
        const adopt = (img) => {
          if (seen.has(img) || !img.complete) return; // incomplete ones get a load event later
          if (img.naturalWidth) schedule(img); else show(img); // broken: show alt/box
        };
        new MutationObserver((records) => {
          if (!cfg.enabled || !cfg.bps) return;
          for (const record of records) {
            for (const node of record.addedNodes) {
              if (node instanceof HTMLImageElement) adopt(node);
              else if (node.querySelectorAll) node.querySelectorAll('img').forEach(adopt);
            }
          }
        }).observe(document, { childList: true, subtree: true });

        return {
          update(next) {
            const wasActive = !!(cfg.enabled && cfg.bps);
            cfg = next;
            if (!cfg.enabled) {
              if (style) style.remove();
              if (svg) svg.remove();
              queue.splice(0).forEach(show);
              post(true);
              return;
            }
            if (!style) { style = document.createElement('style'); style.id = 'dialup-mode-style'; }
            style.textContent = (cfg.bps ? CSS_HIDE : '') + (cfg.gifImages ? CSS_GIF : '') + (cfg.oldFonts ? CSS_FONTS : '')
              + (cfg.retroPage ? CSS_RETRO(cfg.skin) : '') + (cfg.squareCorners ? CSS_SQUARE : '')
              + (cfg.noShadows ? CSS_NO_SHADOWS : '') + (cfg.noAnimations ? CSS_NO_MOTION : '') + (cfg.underlineLinks ? CSS_LINKS : '');
            if (!style.isConnected) attach(style);
            if (cfg.gifImages) ensureSvg();
            // Turned on mid-page: don't re-hide what's already loaded; the next page trickles in.
            if (!wasActive) document.querySelectorAll('img').forEach((img) => { if (img.complete) { seen.add(img); show(img); } });
            if (!cfg.bps) queue.splice(0).forEach(show);
            post(true); // a fresh page always reports, so a stale "(n items remaining)" clears
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
