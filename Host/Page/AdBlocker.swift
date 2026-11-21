import CryptoKit
import Foundation
import WebKit

/// Native ad and tracker blocking with WebKit content rule lists (the engine Safari's blockers use).
/// Requests to well-known ad/tracking networks are blocked before they load, and a few standard
/// ad containers are hidden. The domain list is our own (domain names, not a copied filter list).
@MainActor
enum AdBlocker {
    static let domains = [
        // ad serving and exchanges
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
        "googletagservices.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net",
        "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com", "indexww.com", "adform.net",
        "smartadserver.com", "teads.tv", "yieldlab.net", "33across.com", "sharethrough.com", "triplelift.com",
        "bidswitch.net", "contextweb.com", "lijit.com", "sovrn.com", "media.net", "improvedigital.com",
        "livewrapped.com", "relevant-digital.com", "adnami.io", "seenthis.se", "lwadm.com", "adroll.com",
        "taboola.com", "outbrain.com", "revcontent.com", "mgid.com", "zemanta.com", "yieldmo.com",
        "spotxchange.com", "springserve.com", "smaato.net", "inmobi.com", "applovin.com", "unityads.unity3d.com",
        // ad verification / measurement
        "moatads.com", "doubleverify.com", "adsafeprotected.com", "scorecardresearch.com", "quantserve.com",
        "imrworldwide.com", "chartbeat.net",
        // tracking / data brokers
        "google-analytics.com", "googletagmanager.com", "demdex.net", "everesttech.net", "rlcdn.com",
        "bluekai.com", "krxd.net", "agkn.com", "adsymptotic.com", "crwdcntrl.net", "exelator.com",
        "hotjar.com", "clarity.ms", "mouseflow.com", "fullstory.com",
    ]

    /// Standard ad containers (kept narrow on purpose so ordinary page parts aren't hidden).
    static let hideSelectors = [
        "ins.adsbygoogle", "[id^='google_ads_']", "iframe[id^='google_ads_iframe']", "[id^='div-gpt-ad']",
        "[data-google-query-id]", "iframe[src*='doubleclick.net']", "iframe[src*='googlesyndication.com']",
        "[data-ad-slot]", "[data-ad-unit]",
    ]

    /// A content-blocker `url-filter` matching `domain` and all its subdomains, any scheme and port,
    /// and nothing else (not `notdoubleclick.net`, not `doubleclick.net.example.com`).
    static func urlFilter(for domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        return "^[^:]+://([^/:]+\\.)?\(escaped)[/:]"
    }

    static var rulesJSON: String {
        var rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": urlFilter(for: domain)], "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": ".*"],
                      "action": ["type": "css-display-none", "selector": hideSelectors.joined(separator: ", ")]])
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: .sortedKeys)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static let identifierPrefix = "dialup-adblock-"

    /// The compiled list's identifier carries a hash of the rules, so a changed list is
    /// recompiled while an unchanged one is looked up from WebKit's on-disk cache.
    static var identifier: String {
        let digest = SHA256.hash(data: Data(rulesJSON.utf8))
        return identifierPrefix + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static var compiled: WKContentRuleList?
    private static var loading: Task<WKContentRuleList?, Never>?

    /// The rule list: from WebKit's cache when the rules are unchanged since the last launch,
    /// otherwise compiled (and cached for next time). Concurrent callers share one load.
    static func ruleList() async -> WKContentRuleList? {
        if let compiled { return compiled }
        if let loading { return await loading.value }
        let task = Task { await lookUpOrCompile() }
        loading = task
        let list = await task.value
        compiled = list
        loading = nil
        return list
    }

    private static func lookUpOrCompile() async -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { return nil }
        let id = identifier
        if let cached = try? await store.contentRuleList(forIdentifier: id) { return cached }
        do {
            let list = try await store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: rulesJSON)
            await removeStaleLists(in: store, keeping: id)
            return list
        } catch {
            NSLog("Dialup ad blocker failed to compile: %@", error.localizedDescription)
            return nil
        }
    }

    /// Deletes lists compiled from older versions of the rules.
    private static func removeStaleLists(in store: WKContentRuleListStore, keeping current: String) async {
        let ids = await store.availableIdentifiers() ?? []
        for id in ids where id.hasPrefix(identifierPrefix) && id != current {
            try? await store.removeContentRuleList(forIdentifier: id)
        }
    }

    /// Applies the `blockAds` preference to a window's pages (takes effect on the next page load).
    static func update(_ controller: WKUserContentController) {
        if let compiled {
            install(compiled, on: controller)
            return
        }
        Task {
            // The preference is read after the (first-launch) compile, so the last change wins.
            guard let list = await ruleList() else { return }
            install(list, on: controller)
        }
    }

    private static func install(_ list: WKContentRuleList, on controller: WKUserContentController) {
        controller.remove(list)
        if PreferencesStore.shared.preferences.blockAds { controller.add(list) }
    }
}
