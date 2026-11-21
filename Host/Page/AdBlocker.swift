import Foundation
import WebKit

/// Native ad and tracker blocking with WebKit content rule lists (the engine Safari's blockers use).
/// Requests to well-known ad/tracking networks are blocked before they load, and a few standard
/// ad containers are hidden. The domain list is our own (domain names, not a copied filter list).
@MainActor
enum AdBlocker {
    static let identifier = "dialup-adblock-v1"

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

    static var rulesJSON: String {
        var rules: [[String: Any]] = domains.map { domain in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
            return ["trigger": ["url-filter": "^[^:]+://([^/:]+\\.)?\(escaped)[/:]"], "action": ["type": "block"]]
        }
        rules.append(["trigger": ["url-filter": ".*"],
                      "action": ["type": "css-display-none", "selector": hideSelectors.joined(separator: ", ")]])
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static var compiled: WKContentRuleList?
    private static var waiting: [(WKContentRuleList?) -> Void] = []

    /// Compiles once per launch (WebKit caches the compiled form on disk).
    static func ruleList(_ done: @escaping (WKContentRuleList?) -> Void) {
        if let compiled { done(compiled); return }
        waiting.append(done)
        guard waiting.count == 1 else { return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rulesJSON) { list, error in
            MainActor.assumeIsolated {
                if let error { NSLog("Dialup ad blocker failed to compile: %@", error.localizedDescription) }
                compiled = list
                let callbacks = waiting
                waiting.removeAll()
                callbacks.forEach { $0(list) }
            }
        }
    }

    /// Turns blocking on or off for a window's pages (takes effect on the next page load).
    static func apply(_ enabled: Bool, to controller: WKUserContentController) {
        ruleList { list in
            guard let list else { return }
            controller.remove(list)
            if enabled { controller.add(list) }
        }
    }
}
