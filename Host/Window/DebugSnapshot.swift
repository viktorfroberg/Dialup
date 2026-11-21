import AppKit
import WebKit

/// Debug helper: `Kikare.app/Contents/MacOS/Kikare -KikareSnapshot /tmp/out.png [-KikareSnapshotDelay 5]`
/// composites the chrome and page web views into one PNG, so the look can be checked
/// without Screen Recording permission. It uses WebKit's own snapshot API.
@MainActor
enum DebugSnapshot {
    static func scheduleIfRequested(chrome: WKWebView, page: WKWebView, in container: NSView) {
        guard let path = UserDefaults.standard.string(forKey: "KikareSnapshot") else { return }
        let delay = UserDefaults.standard.double(forKey: "KikareSnapshotDelay")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 5))
            await write(chrome: chrome, page: page, container: container, to: URL(fileURLWithPath: path))
        }
    }

    private static func write(chrome: WKWebView, page: WKWebView, container: NSView, to url: URL) async {
        guard let chromeImage = try? await chrome.takeSnapshot(configuration: nil) else {
            NSLog("Kikare snapshot: chrome snapshot failed")
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
        chromeImage.draw(in: NSRect(origin: .zero, size: size))
        if let pageImage {
            // Container is flipped; drawing context is not.
            let f = page.frame
            pageImage.draw(in: NSRect(x: f.minX, y: size.height - f.maxY, width: f.width, height: f.height))
        }
        NSGraphicsContext.restoreGraphicsState()
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
            NSLog("Kikare snapshot written to %@", url.path)
        } catch {
            NSLog("Kikare snapshot failed: %@", error.localizedDescription)
        }
    }
}
