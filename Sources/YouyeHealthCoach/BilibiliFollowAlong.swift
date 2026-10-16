import Foundation

/// The follow-along surface is deliberately limited to Bilibili's HTTPS domains. It is not a
/// general in-app browser and never receives health, camera-frame, pose, meal, location, or
/// profile data. Keeping the host rule platform-neutral makes the boundary rule-checkable even
/// where WebKit cannot be compiled.
public enum BilibiliFollowAlongNavigationPolicy {
    public static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "b23.tv"
    }
}

#if canImport(SwiftUI) && canImport(UIKit) && canImport(WebKit)
import SwiftUI
import UIKit
import WebKit

/// A user-initiated, session-only Bilibili page used next to the local camera coach. It does not
/// download, record, or persist a course: WebKit is created with a non-persistent data store and
/// is destroyed when the coaching sheet closes. Actual video availability remains Bilibili's
/// responsibility and must be verified on a real device; this view never claims playback worked.
public struct EphemeralBilibiliFollowAlongView: UIViewRepresentable {
    public let url: URL
    public let onBlockedNavigation: () -> Void
    public let onLoadUnavailable: () -> Void

    public init(
        url: URL,
        onBlockedNavigation: @escaping () -> Void = {},
        onLoadUnavailable: @escaping () -> Void = {}
    ) {
        self.url = url
        self.onBlockedNavigation = onBlockedNavigation
        self.onLoadUnavailable = onLoadUnavailable
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onBlockedNavigation: onBlockedNavigation, onLoadUnavailable: onLoadUnavailable)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Do not turn a training lesson into an offline/recorded library. This prevents cookies,
        // local storage and cache from being retained after the current coaching surface closes.
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        // Keep playback inside the same coaching surface so the local camera tile and live cue
        // remain visible. Playback still requires the owner's tap and remains controlled by
        // Bilibili; the App neither auto-plays nor extracts a media URL.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // `makeUIView` is also a defensive boundary for values restored from private JSON. Do
        // not rely on the presenting UI having already validated the initial target: no first
        // navigation is issued if that data is malformed or no longer a permitted Bilibili URL.
        guard BilibiliFollowAlongNavigationPolicy.isAllowed(url) else {
            onBlockedNavigation()
            return webView
        }
        // Force a fresh request for this owner-initiated session. No URLSession, file download,
        // media capture, or custom video/player SDK is involved.
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        return webView
    }

    public func updateUIView(_: WKWebView, context _: Context) {}

    public static func dismantleUIView(_ webView: WKWebView, coordinator _: Coordinator) {
        // Stop third-party playback/network activity when the user dismisses live coaching. The
        // transient website data store is then released with this web view rather than becoming
        // a reusable on-device video cache.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    public final class Coordinator: NSObject, WKNavigationDelegate {
        private let onBlockedNavigation: () -> Void
        private let onLoadUnavailable: () -> Void

        init(onBlockedNavigation: @escaping () -> Void, onLoadUnavailable: @escaping () -> Void) {
            self.onBlockedNavigation = onBlockedNavigation
            self.onLoadUnavailable = onLoadUnavailable
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let targetURL = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            guard BilibiliFollowAlongNavigationPolicy.isAllowed(targetURL) else {
                decisionHandler(.cancel)
                onBlockedNavigation()
                return
            }
            // Bilibili commonly uses a new-window target for an ordinary video/detail route.
            // Keep it in the same ephemeral, host-restricted surface rather than opening a
            // general external browser while the camera coaching session is active.
            if navigationAction.targetFrame == nil {
                webView.load(URLRequest(url: targetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        public func webView(
            _: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            // A navigation can successfully leave the provisional phase and still resolve to
            // an HTTP error page. Treat that as an unavailable lesson so the visible coaching
            // screen offers the local-monitor-only fallback instead of leaving a blank/failed
            // third-party surface beside an active camera session.
            if let response = navigationResponse.response as? HTTPURLResponse,
               !(200..<400).contains(response.statusCode) {
                decisionHandler(.cancel)
                onLoadUnavailable()
                return
            }
            decisionHandler(.allow)
        }

        public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation?, withError _: Error) {
            onLoadUnavailable()
        }

        public func webView(_: WKWebView, didFail _: WKNavigation?, withError _: Error) {
            // This is the post-commit WKNavigationDelegate callback. Keeping its exact system
            // signature matters: an extra WKWebView parameter compiles as an unrelated method
            // but is never called by WebKit, which previously left some failed lessons blank.
            onLoadUnavailable()
        }

        public func webViewWebContentProcessDidTerminate(_: WKWebView) {
            // Memory pressure or a WebKit process crash must produce the same honest fallback;
            // never imply that a lesson is still playable because the containing sheet remains.
            onLoadUnavailable()
        }
    }
}
#endif
