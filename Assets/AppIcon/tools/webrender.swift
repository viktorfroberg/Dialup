import AppKit
import WebKit
// usage: webrender in.svg out.png size   — renders an SVG with WebKit onto a transparent canvas
let a = CommandLine.arguments
let input = URL(fileURLWithPath: a[1]), output = URL(fileURLWithPath: a[2]), n = CGFloat(Int(a[3])!)
let app = NSApplication.shared
@MainActor final class R: NSObject, WKNavigationDelegate {
  let web = WKWebView(frame: NSRect(x: 0, y: 0, width: n, height: n))
  func start() {
    web.setValue(false, forKey: "drawsBackground")
    web.navigationDelegate = self
    let html = "<html><body style='margin:0;background:transparent'><img src='\(input.lastPathComponent)' style='width:\(Int(n))px;height:\(Int(n))px;display:block'></body></html>"
    let work = FileManager.default.temporaryDirectory.appendingPathComponent("webrender-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    try! FileManager.default.copyItem(at: input, to: work.appendingPathComponent(input.lastPathComponent))
    let page = work.appendingPathComponent("index.html")
    try! html.write(to: page, atomically: true, encoding: .utf8)
    web.loadFileURL(page, allowingReadAccessTo: work)
  }
  func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      let cfg = WKSnapshotConfiguration(); cfg.snapshotWidth = NSNumber(value: Double(n) / Double(NSScreen.main?.backingScaleFactor ?? 2))
      cfg.rect = NSRect(x: 0, y: 0, width: n, height: n)
      w.takeSnapshot(with: cfg) { img, err in
        guard let img, let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("fail \(String(describing: err))"); exit(1) }
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: output)
        print("ok \(rep.pixelsWide)x\(rep.pixelsHigh)"); exit(0)
      }
    }
  }
}
let r = MainActor.assumeIsolated { R() }
MainActor.assumeIsolated { r.start() }
app.run()
