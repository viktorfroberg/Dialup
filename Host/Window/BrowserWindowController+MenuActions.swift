import AppKit

/// Native menu actions (see MainMenu), reached through the responder chain. They share the
/// navigation and tab helpers with the host commands.
extension BrowserWindowController: NSMenuItemValidation {
    /// View → Zoom In/Out steps through these page zoom factors.
    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    // MARK: Dialogs drawn by the chrome

    @objc func openSetupWizard(_ sender: Any?) { emit("openWizard", [:]) }
    @objc func openSettings(_ sender: Any?) { emit("openSettings", ["tab": "general"]) }

    @objc func openLocation(_ sender: Any?) {
        window?.makeFirstResponder(chromeView)
        emit("focusAddress", [:])
    }

    @objc func findInPage(_ sender: Any?) { emit("openFind", [:]) }
    @objc func findNext(_ sender: Any?) { emit("findAgain", ["backwards": false]) }
    @objc func findPrevious(_ sender: Any?) { emit("findAgain", ["backwards": true]) }
    /// ⌘D: the chrome shows its Add to Favorites dialog, which then sends `addFavorite`.
    @objc func addToFavorites(_ sender: Any?) { emit("addFavorite", [:]) }

    // MARK: Tabs

    @objc func newTab(_ sender: Any?) { openInNewTabOrWindow(Self.homeURL) }
    /// ⌘W closes the current tab; the last tab closes the window.
    @objc func closeTabOrWindow(_ sender: Any?) { closeTab(at: tabs.activeIndex) }
    @objc func reopenClosedTab(_ sender: Any?) { reopenClosedTab() }
    @objc func selectNextTab(_ sender: Any?) { selectTab(at: tabs.nextIndex) }
    @objc func selectPreviousTab(_ sender: Any?) { selectTab(at: tabs.previousIndex) }
    /// ⌘1…⌘9; the item's tag is the tab number.
    @objc func selectTabByNumber(_ sender: NSMenuItem) { selectTab(at: min(sender.tag, tabs.count) - 1) }

    // MARK: Navigation

    @objc func dialupBack(_ sender: Any?) { goBack() }
    @objc func dialupForward(_ sender: Any?) { goForward() }
    @objc func dialupReload(_ sender: Any?) { reload() }
    @objc func dialupStop(_ sender: Any?) { stopLoading() }
    @objc func dialupHome(_ sender: Any?) { goHome() }

    // MARK: View

    @objc func zoomIn(_ sender: Any?) { zoom(by: 1) }
    @objc func zoomOut(_ sender: Any?) { zoom(by: -1) }
    /// Back to the Text Size setting's zoom.
    @objc func actualSize(_ sender: Any?) { activeTab.webView.pageZoom = textZoom }

    /// View → Text Size → Largest … Smallest (the item's tag is the `TextSize` index).
    @objc func setTextSize(_ sender: NSMenuItem) {
        guard TextSize.allCases.indices.contains(sender.tag) else { return }
        PreferencesStore.shared.preferences.textSize = TextSize.allCases[sender.tag]
    }

    private func zoom(by step: Int) {
        let webView = activeTab.webView
        let steps = Self.zoomSteps
        // Start from the step nearest the current zoom, so odd values snap back onto the scale.
        let current = steps.indices.min { abs(steps[$0] - webView.pageZoom) < abs(steps[$1] - webView.pageZoom) } ?? 0
        webView.pageZoom = steps[min(max(0, current + step), steps.count - 1)]
    }

    @objc func toggleDialupMode(_ sender: Any?) {
        DialupModeStore.shared.settings.enabled.toggle()
    }

    @objc func reloadChrome(_ sender: Any?) { reloadChrome() }

    @objc func printPage(_ sender: Any?) {
        guard let window else { return }
        let webView = activeTab.webView
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let webView = activeTab.webView
        switch menuItem.action {
        case #selector(dialupBack(_:)): return webView.canGoBack
        case #selector(dialupForward(_:)): return webView.canGoForward
        case #selector(dialupStop(_:)): return webView.isLoading
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)): return tabs.count > 1
        case #selector(reopenClosedTab(_:)): return !closedTabs.isEmpty
        case #selector(addToFavorites(_:)): return ["http", "https"].contains(webView.url?.scheme ?? "")
        case #selector(selectTabByNumber(_:)): return menuItem.tag <= tabs.count
        case #selector(setTextSize(_:)):
            menuItem.state = TextSize.allCases.firstIndex(of: PreferencesStore.shared.preferences.textSize) == menuItem.tag ? .on : .off
            return true
        case #selector(toggleDialupMode(_:)):
            menuItem.state = DialupModeStore.shared.settings.enabled ? .on : .off
            return true
        default: return true
        }
    }
}
