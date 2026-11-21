import AppKit
import WebKit

/// Debug helper: `Dialup.app/Contents/MacOS/Dialup -DialupSnapshot /tmp/out.png [-DialupSnapshotDelay 5]`
/// composites the chrome and page web views into one PNG, so the look can be checked
/// without Screen Recording permission. It uses WebKit's own snapshot API.
/// `-DialupChromeEval "<js>"` runs JavaScript in the chrome 2 s before the snapshot (e.g. open a dialog).
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested(chrome: WKWebView, page: WKWebView, in container: NSView) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "DialupSnapshot") else { return }
        let delay = UserDefaults.standard.double(forKey: "DialupSnapshotDelay")
        let eval = UserDefaults.standard.string(forKey: "DialupChromeEval")
        Task { @MainActor in
            let total = delay > 0 ? delay : 5
            if let eval {
                try? await Task.sleep(for: .seconds(max(0.5, total - 2)))
                chrome.evaluateJavaScript(eval) { _, error in
                    if let error { NSLog("Dialup chrome eval failed: %@", error.localizedDescription) }
                }
                try? await Task.sleep(for: .seconds(2))
            } else {
                try? await Task.sleep(for: .seconds(total))
            }
            await write(chrome: chrome, page: page, container: container, to: URL(fileURLWithPath: path))
        }
        #endif
    }

    private static func write(chrome: WKWebView, page: WKWebView, container: NSView, to url: URL) async {
        guard let chromeImage = try? await chrome.takeSnapshot(configuration: nil) else {
            NSLog("Dialup snapshot: chrome snapshot failed")
            return
        }
        let pageImage = page.isHidden ? nil : try? await page.takeSnapshot(configuration: nil)
        let size = container.bounds.size
        let scale = container.window?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let chromeOnTop = (container as? BrowserLayoutView)?.chromeOnTop ?? false
        let drawPage = {
            // Container is flipped; drawing context is not.
            let f = page.frame
            pageImage?.draw(in: NSRect(x: f.minX, y: size.height - f.maxY, width: f.width, height: f.height))
        }
        if chromeOnTop { drawPage() }
        chromeImage.draw(in: NSRect(origin: .zero, size: size))
        if !chromeOnTop { drawPage() }
        NSGraphicsContext.restoreGraphicsState()
        // Window-level Core Image filters (dial-up mode) aren't part of WebKit snapshots,
        // so apply the same filters here to preview the result.
        var output = rep
        let settings = DialupMode.shared.settings
        let filters = DialupModeRenderer.filters(for: settings, backingScale: scale)
        if !filters.isEmpty, let full = CIImage(bitmapImageRep: rep) {
            // Filter the whole window, or only the page rect (CI coordinates: bottom-left origin, pixels).
            let f = page.frame
            let region = settings.includeChrome ? full.extent
                : CGRect(x: f.minX * scale, y: (size.height - f.maxY) * scale, width: f.width * scale, height: f.height * scale)
            var image = full.cropped(to: region)
            for filter in filters {
                filter.setValue(image, forKey: kCIInputImageKey)
                image = filter.outputImage?.cropped(to: region) ?? image
            }
            output = NSBitmapImageRep(ciImage: image.composited(over: full))
        }
        do {
            try output.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("Dialup snapshot written to %@", url.path)
        } catch {
            NSLog("Dialup snapshot failed: %@", error.localizedDescription)
        }
    }
}
