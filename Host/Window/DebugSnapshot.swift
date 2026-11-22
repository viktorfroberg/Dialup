import AppKit
import WebKit

/// Debug helper: `Dialup.app/Contents/MacOS/Dialup -DialupSnapshot /tmp/out.png [-DialupSnapshotDelay 5]`
/// composites the chrome and page web views into one PNG, so the look can be checked
/// without Screen Recording permission. It uses WebKit's own snapshot API.
/// `-DialupChromeEval "<js>"` runs JavaScript in the chrome 2 s before the snapshot (e.g. open a dialog).
/// `-DialupChromeEvalLead 0.2` changes that 2 s.
/// `-DialupSnapshotFrames 20 -DialupSnapshotInterval 0.5` writes a sequence (out-000.png, …) for GIFs.
/// Debug builds only.
@MainActor
enum DebugSnapshot {
    private static let defaultDelay = 5.0
    /// How long before the snapshot `-DialupChromeEval` runs, so the chrome can react.
    private static let evalLeadTime = 2.0

    static func scheduleIfRequested(chrome: WKWebView, page: WKWebView, in container: NSView) {
        #if DEBUG
        guard let path = UserDefaults.standard.string(forKey: "DialupSnapshot") else { return }
        let delay = UserDefaults.standard.double(forKey: "DialupSnapshotDelay")
        let eval = UserDefaults.standard.string(forKey: "DialupChromeEval")
        let storedLead = UserDefaults.standard.double(forKey: "DialupChromeEvalLead")
        let lead = storedLead > 0 ? storedLead : evalLeadTime
        Task { @MainActor in
            let total = delay > 0 ? delay : defaultDelay
            if let eval {
                try? await Task.sleep(for: .seconds(max(0.5, total - lead)))
                do {
                    _ = try await chrome.evaluateJavaScript(eval, contentWorld: .page) // this overload tolerates an undefined result
                } catch {
                    NSLog("Dialup chrome eval failed: %@", error.localizedDescription)
                }
                try? await Task.sleep(for: .seconds(lead))
            } else {
                try? await Task.sleep(for: .seconds(total))
            }
            let frames = max(1, UserDefaults.standard.integer(forKey: "DialupSnapshotFrames"))
            let interval = UserDefaults.standard.double(forKey: "DialupSnapshotInterval")
            for frame in 0..<frames {
                let url = URL(fileURLWithPath: path)
                let target = frames == 1 ? url : url.deletingPathExtension()
                    .appendingPathExtension(String(format: "%03d", frame)).appendingPathExtension("png")
                await write(chrome: chrome, page: page, container: container, to: target)
                if frame < frames - 1 { try? await Task.sleep(for: .seconds(interval > 0 ? interval : 0.5)) }
            }
        }
        #endif
    }

    #if DEBUG
    private static func write(chrome: WKWebView, page initialPage: WKWebView, container: NSView, to url: URL) async {
        // The visible tab may have changed since the snapshot was scheduled.
        let page = ((container as? BrowserLayoutView)?.pageView as? WKWebView) ?? initialPage
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
        let settings = DialupModeStore.shared.settings
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
    #endif
}
