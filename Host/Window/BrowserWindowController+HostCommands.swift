import AppKit
import WebKit

/// Carries out the chrome's commands (see `HostCommand` and docs/host-api.md).
extension BrowserWindowController: HostCommandHandling {
    /// The `history` command lists at most this many entries.
    private static let maxHistoryItems = 15
    private static let maxLogMessageLength = 2000

    func perform(_ command: HostCommand) -> Any? {
        switch command {
        case .ready: return chromeDidBecomeReady()
        case .setInsets(let insets): layoutView.insets = insets
        case .overlay(let open): setOverlay(open)
        case .log(let message): NSLog("Dialup chrome: %@", String(message.prefix(Self.maxLogMessageLength)))

        case .navigate(let input): navigate(to: input)
        case .search(let query): search(for: query)
        case .back: goBack()
        case .forward: goForward()
        case .reload: reload()
        case .stop: stopLoading()
        case .home: goHome()
        case .focusPage: focusPage()
        case .history(let direction): return historyItems(direction)
        case .goHistory(let offset):
            let webView = activeTab.webView
            if let item = webView.backForwardList.item(at: offset) { webView.go(to: item) }
        case .wayback(let year): openInWayback(year: year)
        case .find(let text, let backwards, let caseSensitive):
            find(text, backwards: backwards, caseSensitive: caseSensitive)
        case .securityInfo: return securityInfo()

        case .windowClose: window?.performClose(nil)
        case .windowMinimize: window?.performMiniaturize(nil)
        case .windowZoom: window?.performZoom(nil)
        case .windowDrag: dragWindow()
        case .titlebarDoubleClick: titlebarDoubleClick()
        case .newTab(let input):
            let prefs = PreferencesStore.shared.preferences
            let url = input.flatMap { AddressResolver.resolve($0, searchTemplate: prefs.searchTemplate, startURL: Preferences.startURL) }
            openInNewTabOrWindow(url ?? Self.homeURL)
        case .closeTab(let id): if let index = tabIndex(id: id) { closeTab(at: index) }
        case .selectTab(let id): if let index = tabIndex(id: id) { selectTab(at: index) }
        case .menuAction(let action):
            // Sent after the overlay has closed, so it reaches the page (or whatever had focus before).
            NSApp.sendAction(action.selector, to: nil, from: nil)
        case .popupMenu(let items, let point):
            // layoutView is flipped and the chrome fills it, so chrome CSS pixels map directly.
            return NativePopupMenu.pick(from: items, at: point, in: layoutView)

        case .prefsGet: return preferencesPayload
        case .prefsSet(let patch):
            PreferencesStore.shared.preferences = PreferencesStore.shared.preferences.merging(patch)
        case .dialupModeGet: return DialupModeStore.shared.settings.dictionary
        case .dialupModeSet(let patch):
            DialupModeStore.shared.settings = DialupModeStore.shared.settings.merging(patch)
        case .dialupModePreset(let id):
            if let preset = DialupModeSettings.presets[id] { DialupModeStore.shared.settings = preset }
        case .clearData(let kind): clearWebsiteData(kind)
        case .importBookmarks:
            guard let window else { break }
            Task { [weak self] in
                guard let result = await BookmarksPanels.importFavorites(in: window) else { return }
                self?.emit("bookmarksImported", ["added": result.added, "found": result.found])
            }
        case .exportBookmarks:
            guard let window else { break }
            Task { await BookmarksPanels.exportFavorites(in: window) }
        case .addFavorite(let title, let url):
            PreferencesStore.shared.preferences.addFavorites([QuickLink(title: title, url: url)])

        case .checkForUpdates: Updates.shared.checkForUpdates(nil)
        case .updateChoice(let choice): Updates.shared.choose(choice)
        case .openDownload(let path, let reveal):
            // Never open arbitrary paths from the chrome: only files this window finished downloading.
            guard completedDownloads.contains(path) else { return nil }
            let url = URL(fileURLWithPath: path)
            if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }

        case .sound(let sound): SoundEffects.shared.play(sound)
        case .soundSet(let enabled): SoundEffects.shared.isEnabled = enabled
        }
        return nil
    }

    // MARK: Helpers

    /// Back/Forward dropdown entries; `offset` is what `goHistory` takes (negative = back).
    private func historyItems(_ direction: HostCommand.HistoryDirection) -> [[String: Any]] {
        let list = activeTab.webView.backForwardList
        let back = direction == .back
        let items = back ? Array(list.backList.reversed()) : list.forwardList
        return items.prefix(Self.maxHistoryItems).enumerated().map { index, item in
            [
                "offset": (index + 1) * (back ? -1 : 1),
                "title": item.title ?? "",
                "url": item.url.absoluteString,
            ]
        }
    }

    /// Reloads the current page as the Wayback Machine saw it around the chosen year.
    private func openInWayback(year: Int) {
        guard let current = activeTab.sessionURL, ["http", "https"].contains(current.scheme ?? ""),
              let url = URL(string: "https://web.archive.org/web/\(year)0601000000/\(current.absoluteString)") else { return }
        SoundEffects.shared.play(.click)
        load(url)
    }

    /// Find in page (the chrome draws the retro Find dialog). The result goes back as `findResult`.
    private func find(_ text: String, backwards: Bool, caseSensitive: Bool) {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = caseSensitive
        configuration.wraps = true
        let webView = activeTab.webView
        Task { [weak self] in
            let result = try? await webView.find(text, configuration: configuration)
            self?.emit("findResult", ["found": result?.matchFound ?? false])
        }
    }

    /// Certificate summary for the padlock dialog; nil for non-HTTPS pages.
    private func securityInfo() -> [String: Any]? {
        let webView = activeTab.webView
        guard let url = webView.url, url.scheme == "https" else { return nil }
        var info: [String: Any] = ["host": url.host ?? "", "secure": webView.hasOnlySecureContent]
        if let trust = webView.serverTrust,
           let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
            if let leaf = chain.first { info["subject"] = SecCertificateCopySubjectSummary(leaf) as String? ?? "" }
            if chain.count > 1 { info["issuer"] = SecCertificateCopySubjectSummary(chain[1]) as String? ?? "" }
        }
        return info
    }

    private func clearWebsiteData(_ kind: HostCommand.ClearDataKind) {
        let types: Set<String> = switch kind {
        case .cache: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
        case .all: WKWebsiteDataStore.allWebsiteDataTypes()
        }
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    /// Same trick Tauri uses: start a native window drag from the title bar's mouse-down.
    /// The JS message arrives asynchronously, so only drag while the button is still held.
    private func dragWindow() {
        guard NSEvent.pressedMouseButtons & 1 != 0,
              let event = (window as? DialupWindow)?.lastLeftMouseDown ?? NSApp.currentEvent else { return }
        window?.performDrag(with: event)
    }

    /// Title bar double-click follows the user's macOS setting (Zoom / Minimize / nothing).
    private func titlebarDoubleClick() {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
    }
}

extension HostCommand.MenuAction {
    /// The responder-chain action this menu item sends.
    var selector: Selector {
        switch self {
        case .newWindow: #selector(AppDelegate.newWindow(_:))
        case .performClose: #selector(NSWindow.performClose(_:))
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        case .toggleFullScreen: #selector(NSWindow.toggleFullScreen(_:))
        }
    }
}
