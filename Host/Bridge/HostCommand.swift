import AppKit

/// A command from the chrome (`host.call(cmd, args)`), parsed and validated once.
/// See docs/host-api.md for the JSON form of each command.
enum HostCommand {
    // Startup and layout
    case ready
    case setInsets(NSEdgeInsets)
    case overlay(open: Bool)
    case log(message: String)

    // Navigation in the active tab
    case navigate(input: String)
    case search(query: String)
    case back, forward, reload, stop, home
    case focusPage
    case history(HistoryDirection)
    case goHistory(offset: Int)
    case wayback(year: Int)
    case find(text: String, backwards: Bool, caseSensitive: Bool)
    case securityInfo

    // Window and tabs
    case windowClose, windowMinimize, windowZoom, windowDrag, titlebarDoubleClick
    case newTab(input: String?)
    case closeTab(id: Int)
    case selectTab(id: Int)
    case menuAction(MenuAction)
    case popupMenu(items: [[String: Any]], at: NSPoint)

    // Settings and data
    case prefsGet
    case prefsSet(patch: [String: Any])
    case dialupModeGet
    case dialupModeSet(patch: [String: Any])
    case dialupModePreset(id: String)
    case clearData(ClearDataKind)
    case importBookmarks, exportBookmarks
    case addFavorite(title: String, url: String)
    /// Open or reveal a file this window downloaded (only paths from completed downloads are accepted).
    case openDownload(path: String, reveal: Bool)
    case checkForUpdates
    /// Ask macOS to make Dialup the default web browser (macOS asks the user to confirm).
    case makeDefaultBrowser
    /// Pick the downloads folder in a native panel; replies `{ path }` (null if cancelled).
    case chooseDownloadFolder
    /// A button in the update dialog.
    case updateChoice(UpdateChoice)

    // Sounds
    case sound(SoundEffects.Sound)
    case soundSet(enabled: Bool)

    enum HistoryDirection: String { case back, forward }

    enum ClearDataKind: String {
        /// Disk, memory and fetch caches.
        case cache
        /// Everything websites stored: caches, cookies, local storage…
        case all
    }

    /// Items of the chrome's own menu bar that are forwarded to the responder chain.
    /// An allowlist: the chrome can't send arbitrary selectors.
    enum MenuAction: String {
        case newWindow, performClose, cut, copy, paste, selectAll, toggleFullScreen
    }

    /// Years the Wayback button accepts.
    static let waybackYears = 1996...2030

    enum ParseError: Error, Equatable {
        case unknownCommand(String)
        case invalidArguments(String)
    }

    /// Parses the bridge's `(cmd, args)`. Optional arguments get the defaults documented in
    /// docs/host-api.md; missing required or invalid arguments throw `.invalidArguments`.
    init(_ cmd: String, _ args: [String: Any]) throws(ParseError) {
        let a = Arguments(args)
        let invalid = ParseError.invalidArguments(cmd)
        switch cmd {
        case "ready": self = .ready
        case "setInsets":
            self = .setInsets(NSEdgeInsets(top: a.number("top") ?? 0, left: a.number("left") ?? 0,
                                           bottom: a.number("bottom") ?? 0, right: a.number("right") ?? 0))
        case "overlay": self = .overlay(open: a.bool("open") ?? false)
        case "log": self = .log(message: a.string("message") ?? "")

        case "navigate":
            guard let input = a.string("input") else { throw invalid }
            self = .navigate(input: input)
        case "search":
            guard let query = a.nonEmptyString("query") else { throw invalid }
            self = .search(query: query)
        case "back": self = .back
        case "forward": self = .forward
        case "reload": self = .reload
        case "stop": self = .stop
        case "home": self = .home
        case "focusPage": self = .focusPage
        case "history":
            // Anything but "forward" means back, as the chrome has always relied on.
            self = .history(a.string("direction") == "forward" ? .forward : .back)
        case "goHistory":
            guard let offset = a.int("offset") else { throw invalid }
            self = .goHistory(offset: offset)
        case "wayback":
            guard let year = a.int("year"), Self.waybackYears.contains(year) else { throw invalid }
            self = .wayback(year: year)
        case "find":
            guard let text = a.nonEmptyString("text") else { throw invalid }
            self = .find(text: text, backwards: a.bool("backwards") ?? false, caseSensitive: a.bool("caseSensitive") ?? false)
        case "securityInfo": self = .securityInfo
        case "openDownload":
            guard let path = a.nonEmptyString("path") else { throw invalid }
            self = .openDownload(path: path, reveal: a.bool("reveal") ?? false)
        case "checkForUpdates": self = .checkForUpdates
        case "makeDefaultBrowser": self = .makeDefaultBrowser
        case "chooseDownloadFolder": self = .chooseDownloadFolder
        case "updateChoice":
            guard let choice = a.string("choice").flatMap(UpdateChoice.init(rawValue:)) else { throw invalid }
            self = .updateChoice(choice)

        case "windowClose": self = .windowClose
        case "windowMinimize": self = .windowMinimize
        case "windowZoom": self = .windowZoom
        case "windowDrag": self = .windowDrag
        case "titlebarDoubleClick": self = .titlebarDoubleClick
        case "newTab": self = .newTab(input: a.string("url"))
        case "closeTab":
            guard let id = a.int("id") else { throw invalid }
            self = .closeTab(id: id)
        case "selectTab":
            guard let id = a.int("id") else { throw invalid }
            self = .selectTab(id: id)
        case "menuAction":
            guard let action = a.string("action").flatMap(MenuAction.init(rawValue:)) else { throw invalid }
            self = .menuAction(action)
        case "popupMenu":
            self = .popupMenu(items: args["items"] as? [[String: Any]] ?? [],
                              at: NSPoint(x: a.number("x") ?? 0, y: a.number("y") ?? 0))

        case "prefsGet": self = .prefsGet
        case "prefsSet": self = .prefsSet(patch: args)
        case "dialupModeGet": self = .dialupModeGet
        case "dialupModeSet": self = .dialupModeSet(patch: args)
        case "dialupModePreset":
            guard let id = a.string("id"), DialupModeSettings.presets[id] != nil else { throw invalid }
            self = .dialupModePreset(id: id)
        case "clearData":
            // A missing kind clears the cache; an unknown kind clears nothing.
            guard let kind = ClearDataKind(rawValue: a.string("what") ?? ClearDataKind.cache.rawValue) else { throw invalid }
            self = .clearData(kind)
        case "importBookmarks": self = .importBookmarks
        case "exportBookmarks": self = .exportBookmarks
        case "addFavorite":
            guard let url = a.string("url") else { throw invalid }
            self = .addFavorite(title: a.string("title") ?? url, url: url)

        case "sound":
            // The modem handshake belongs to Dial-up Mode; the chrome can't trigger it.
            guard let sound = a.string("name").flatMap(SoundEffects.Sound.init(rawValue:)), sound != .modem else { throw invalid }
            self = .sound(sound)
        case "soundSet": self = .soundSet(enabled: a.bool("enabled") ?? true)

        default: throw .unknownCommand(cmd)
        }
    }
}

/// Typed reads from a JSON arguments object. JS numbers arrive as NSNumber.
private struct Arguments {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }

    func string(_ key: String) -> String? { raw[key] as? String }
    func nonEmptyString(_ key: String) -> String? { string(key).flatMap { $0.isEmpty ? nil : $0 } }
    func bool(_ key: String) -> Bool? { raw[key] as? Bool }
    func int(_ key: String) -> Int? { (raw[key] as? NSNumber)?.intValue }
    func number(_ key: String) -> CGFloat? { (raw[key] as? NSNumber).map { CGFloat($0.doubleValue) } }
}
