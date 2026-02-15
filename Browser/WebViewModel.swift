//
//  WebViewModel.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI
import WebKit
import Combine

// MARK: - WebView Model

class WebViewModel: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView = WKWebView()

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL = ""
    @Published var ogData = OGMetadata()
    @Published var ogImage: NSImage?
    @Published var twitterOgImage: NSImage?
    @Published var faviconImage: NSImage?
    @Published var pageBackgroundColor: Color = .white

    // Buffer pending metadata so we only apply it once isLoading is false
    private var pendingOgData: OGMetadata?
    private var pendingOgImage: NSImage?
    private var pendingTwitterOgImage: NSImage?
    private var pendingFaviconImage: NSImage?
    private var pendingBgColor: Color?

    private var observers: [NSKeyValueObservation] = []
    private var navigationDelegate: WebNavigationDelegate?
    private var headObserverDebounce: DispatchWorkItem?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "headChanged" else { return }
        // Debounce: pages often mutate <head> many times in quick succession
        headObserverDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.fetchOGMetadata()
        }
        headObserverDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    override init() {
        super.init()
        let delegate = WebNavigationDelegate(model: self)
        self.navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        // Inject MutationObserver to watch <head> for meta/link tag changes
        let observerJS = """
        (function() {
            if (window.__headObserverInstalled) return;
            window.__headObserverInstalled = true;
            var observer = new MutationObserver(function(mutations) {
                var relevant = mutations.some(function(m) {
                    if (m.type === 'attributes') {
                        var t = m.target.tagName;
                        return t === 'META' || t === 'LINK';
                    }
                    for (var i = 0; i < m.addedNodes.length; i++) {
                        var t = m.addedNodes[i].tagName;
                        if (t === 'META' || t === 'LINK') return true;
                    }
                    for (var i = 0; i < m.removedNodes.length; i++) {
                        var t = m.removedNodes[i].tagName;
                        if (t === 'META' || t === 'LINK') return true;
                    }
                    return false;
                });
                if (relevant) {
                    window.webkit.messageHandlers.headChanged.postMessage('changed');
                }
            });
            observer.observe(document.head, { childList: true, attributes: true, subtree: true });
        })();
        """
        let script = WKUserScript(source: observerJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(self, name: "headChanged")

        observers = [
            webView.observe(\.canGoBack, options: .new) { [weak self] _, change in
                DispatchQueue.main.async { self?.canGoBack = change.newValue ?? false }
            },
            webView.observe(\.canGoForward, options: .new) { [weak self] _, change in
                DispatchQueue.main.async { self?.canGoForward = change.newValue ?? false }
            },
            webView.observe(\.isLoading, options: .new) { [weak self] _, change in
                DispatchQueue.main.async {
                    self?.isLoading = change.newValue ?? false
                    if !(change.newValue ?? false) { self?.flushPendingMetadata() }
                }
            },
            webView.observe(\.url, options: .new) { [weak self] _, change in
                DispatchQueue.main.async {
                    let newURL = change.newValue??.absoluteString ?? ""
                    guard newURL != self?.currentURL else { return }
                    self?.currentURL = newURL
                    // Re-fetch OG data after a short delay for SPA navigations
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.fetchOGMetadata()
                    }
                }
            }
        ]
    }

    func load(_ urlString: String) {
        var urlStr = urlString
        if !urlStr.hasPrefix("about:") && !urlStr.contains("://") {
            urlStr = "https://" + urlStr
        }
        guard let url = URL(string: urlStr) else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stopLoading() { webView.stopLoading() }

    func takeSnapshot(completion: @escaping (NSImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        webView.takeSnapshot(with: config) { image, _ in
            completion(image)
        }
    }

    private func applyMetadata(_ metadata: OGMetadata, ogImage: NSImage?, twitterOgImage: NSImage?, faviconImage: NSImage?, bgColor: Color?) {
        self.ogImage = ogImage
        self.twitterOgImage = twitterOgImage
        self.faviconImage = faviconImage
        self.ogData = metadata
        if let bgColor { self.pageBackgroundColor = bgColor }
    }

    private func flushPendingMetadata() {
        guard let pending = pendingOgData else { return }
        applyMetadata(pending, ogImage: pendingOgImage, twitterOgImage: pendingTwitterOgImage, faviconImage: pendingFaviconImage, bgColor: pendingBgColor)
        pendingOgData = nil
        pendingOgImage = nil
        pendingTwitterOgImage = nil
        pendingFaviconImage = nil
        pendingBgColor = nil
    }

    func fetchOGMetadata() {
        let js = """
            (function() {
                function getMeta(property) {
                    var el = document.querySelector('meta[property="' + property + '"]') ||
                             document.querySelector('meta[name="' + property + '"]');
                    return el ? el.getAttribute('content') || '' : '';
                }
                function getMetaTag(property) {
                    var el = document.querySelector('meta[property="' + property + '"]') ||
                             document.querySelector('meta[name="' + property + '"]');
                    return el ? el.outerHTML : '';
                }
                var icons = [];
                document.querySelectorAll('link[rel="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"], link[rel="apple-touch-icon-precomposed"]').forEach(function(el) {
                    var href = el.getAttribute('href') || '';
                    if (href && !href.startsWith('http')) {
                        href = new URL(href, document.location.origin).href;
                    }
                    if (href) {
                        icons.push({
                            url: href,
                            sizes: el.getAttribute('sizes') || '',
                            rel: el.getAttribute('rel') || '',
                            rawTag: el.outerHTML
                        });
                    }
                });
                var hasFavicon = icons.some(function(i) { return i.rel === 'icon' || i.rel === 'shortcut icon'; });
                var hasTouch = icons.some(function(i) { return i.rel.indexOf('apple-touch-icon') !== -1; });
                if (!hasFavicon) {
                    icons.push({
                        url: document.location.origin + '/favicon.ico',
                        sizes: '',
                        rel: 'shortcut icon',
                        rawTag: '<link rel="shortcut icon" href="/favicon.ico">'
                    });
                }
                if (!hasTouch) {
                    icons.push({
                        url: document.location.origin + '/apple-touch-icon.png',
                        sizes: '180x180',
                        rel: 'apple-touch-icon',
                        rawTag: '<link rel="apple-touch-icon" href="/apple-touch-icon.png">'
                    });
                }
                var favicon = icons.length > 0 ? icons[0].url : '';
                var hasPWA = !!document.querySelector('link[rel="manifest"]');
                var hasViewport = !!document.querySelector('meta[name="viewport"]');
                var canonicalEl = document.querySelector('link[rel="canonical"]');
                var canonical = canonicalEl ? canonicalEl.getAttribute('href') || '' : '';
                var robots = getMeta('robots') || getMeta('googlebot') || '';
                var keywords = getMeta('keywords') || '';
                var generator = getMeta('generator') || '';
                if (!generator) {
                    if (document.querySelector('script#__NEXT_DATA__') || document.querySelector('script[src*="/_next/"]') || typeof self.__next_f !== 'undefined' || (document.getElementById('__next') && (document.querySelector('link[href*="/_next/"]') || document.querySelector('script[src*="/_next/"]')))) generator = 'Next.js';
                    else if (typeof window.__remixContext !== 'undefined' || document.querySelector('script[src*="/build/"]') && document.querySelector('link[href*="/build/"]') && document.querySelector('meta[name="viewport"]')) generator = 'Remix';
                    else if (document.querySelector('meta[name="nuxt"]') || document.querySelector('script#__NUXT_DATA__') || document.querySelector('[id^="__nuxt"]')) generator = 'Nuxt';
                    else if (document.querySelector('#__gatsby')) generator = 'Gatsby';
                    else if (document.querySelector('[data-svelte-h]') || document.querySelector('[class*="svelte-"]')) generator = 'Svelte';
                    else if (document.querySelector('[ng-version]')) generator = 'Angular';
                    else if (document.querySelector('[data-v-]') || document.querySelector('[data-vue-app]') || document.getElementById('__vue-content')) generator = 'Vue';
                    else if (document.querySelector('[data-reactroot]') || document.getElementById('__next')) generator = 'React';
                }
                var lang = document.documentElement.getAttribute('lang') || '';
                var bgColor = '';
                var el = document.body;
                while (el) {
                    var bg = window.getComputedStyle(el).backgroundColor;
                    if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                        bgColor = bg;
                        break;
                    }
                    el = el.parentElement;
                }
                if (!bgColor) bgColor = 'rgb(255, 255, 255)';
                return JSON.stringify({
                    title: getMeta('og:title') || document.title || '',
                    description: getMeta('og:description') || getMeta('description') || '',
                    image: getMeta('og:image') || '',
                    imageTag: getMetaTag('og:image'),
                    twitterImageTag: getMetaTag('twitter:image') || getMetaTag('twitter:image:src'),
                    twitterTitle: getMeta('twitter:title') || getMeta('og:title') || document.title || '',
                    twitterDescription: getMeta('twitter:description') || getMeta('og:description') || getMeta('description') || '',
                    twitterImage: getMeta('twitter:image') || getMeta('twitter:image:src') || getMeta('og:image') || '',
                    favicon: favicon || (document.location.origin + '/favicon.ico'),
                    themeColor: getMeta('theme-color') || '',
                    icons: icons,
                    canonical: canonical,
                    robots: robots,
                    keywords: keywords,
                    generator: generator,
                    lang: lang,
                    hasPWA: hasPWA,
                    hasViewport: hasViewport,
                    bgColor: bgColor,
                    pageURL: document.location.href
                });
            })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            // Discard stale results from a page that's no longer current
            let pageURL = dict["pageURL"] as? String ?? ""
            guard pageURL == self?.currentURL else { return }

            var host = ""
            if let urlStr = self?.webView.url?.absoluteString,
               let url = URL(string: urlStr),
               let h = url.host() {
                host = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
            }

            var icons: [IconInfo] = []
            if let iconDicts = dict["icons"] as? [[String: Any]] {
                icons = iconDicts.compactMap { d in
                    guard let url = d["url"] as? String, !url.isEmpty else { return nil }
                    return IconInfo(
                        url: url,
                        sizes: d["sizes"] as? String ?? "",
                        rel: d["rel"] as? String ?? "",
                        rawTag: d["rawTag"] as? String ?? ""
                    )
                }
            }

            var metadata = OGMetadata(
                title: dict["title"] as? String ?? "",
                description: dict["description"] as? String ?? "",
                imageURL: dict["image"] as? String ?? "",
                imageTag: dict["imageTag"] as? String ?? "",
                twitterTitle: dict["twitterTitle"] as? String ?? "",
                twitterDescription: dict["twitterDescription"] as? String ?? "",
                twitterImage: dict["twitterImage"] as? String ?? "",
                twitterImageTag: dict["twitterImageTag"] as? String ?? "",
                faviconURL: dict["favicon"] as? String ?? "",
                icons: icons,
                themeColor: dict["themeColor"] as? String ?? "",
                canonical: dict["canonical"] as? String ?? "",
                robots: dict["robots"] as? String ?? "",
                keywords: dict["keywords"] as? String ?? "",
                generator: dict["generator"] as? String ?? "",
                lang: dict["lang"] as? String ?? "",
                hasPWA: dict["hasPWA"] as? Bool ?? false,
                hasViewport: dict["hasViewport"] as? Bool ?? false,
                host: host,
                sourceURL: self?.webView.url?.absoluteString ?? ""
            )

            // Prefetch OG images into URL cache and read dimensions
            let ogImageURLs = [metadata.imageURL, metadata.twitterImage, metadata.faviconURL]
                .compactMap { URL(string: $0) }
                .filter { !$0.absoluteString.isEmpty }

            var ogImageSize: (Int, Int)? = nil
            var twitterImageSize: (Int, Int)? = nil
            var prefetchedOgImage: NSImage? = nil
            var prefetchedTwitterImage: NSImage? = nil
            var prefetchedFavicon: NSImage? = nil

            let group = DispatchGroup()
            for url in ogImageURLs {
                group.enter()
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data, let nsImage = NSImage(data: data) {
                        let rep = nsImage.representations.first
                        let pw = rep?.pixelsWide ?? 0
                        let ph = rep?.pixelsHigh ?? 0
                        let w = pw > 0 ? pw : Int(nsImage.size.width)
                        let h = ph > 0 ? ph : Int(nsImage.size.height)
                        if w > 0 && h > 0 {
                            if url.absoluteString == metadata.imageURL && ogImageSize == nil {
                                ogImageSize = (w, h)
                                prefetchedOgImage = nsImage
                            }
                            if url.absoluteString == metadata.twitterImage && twitterImageSize == nil {
                                twitterImageSize = (w, h)
                                prefetchedTwitterImage = nsImage
                            }
                        }
                        if url.absoluteString == metadata.faviconURL {
                            prefetchedFavicon = nsImage
                        }
                    }
                    group.leave()
                }.resume()
            }

            // Prefetch icon images and resolve their actual pixel sizes
            var resolvedIcons = icons
            for (i, icon) in icons.enumerated() {
                guard let url = URL(string: icon.url), !icon.url.isEmpty else { continue }
                group.enter()
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data, let nsImage = NSImage(data: data) {
                        let rep = nsImage.representations.first
                        resolvedIcons[i].image = nsImage
                        let pw = rep?.pixelsWide ?? 0
                        let ph = rep?.pixelsHigh ?? 0
                        // For vector formats (SVG), pixel dims are 0; use point size instead
                        resolvedIcons[i].pixelWidth = pw > 0 ? pw : (nsImage.size.width > 0 ? Int(nsImage.size.width) : nil)
                        resolvedIcons[i].pixelHeight = ph > 0 ? ph : (nsImage.size.height > 0 ? Int(nsImage.size.height) : nil)
                    }
                    group.leave()
                }.resume()
            }

            group.notify(queue: .main) {
                guard let self else { return }
                metadata.icons = resolvedIcons
                if let (w, h) = ogImageSize {
                    metadata.imageWidth = w
                    metadata.imageHeight = h
                }
                if let (w, h) = twitterImageSize {
                    metadata.twitterImageWidth = w
                    metadata.twitterImageHeight = h
                }
                let bgColor = (dict["bgColor"] as? String).flatMap { Self.parseCSS(rgb: $0) }

                if self.isLoading {
                    // Buffer until isLoading becomes false so content + opacity change together
                    self.pendingOgData = metadata
                    self.pendingOgImage = prefetchedOgImage
                    self.pendingTwitterOgImage = prefetchedTwitterImage
                    self.pendingFaviconImage = prefetchedFavicon
                    self.pendingBgColor = bgColor
                } else {
                    // Already done loading, apply immediately
                    self.applyMetadata(metadata, ogImage: prefetchedOgImage, twitterOgImage: prefetchedTwitterImage, faviconImage: prefetchedFavicon, bgColor: bgColor)
                }
            }
        }
    }

    private static func parseCSS(rgb: String) -> Color? {
        let cleaned = rgb.replacingOccurrences(of: " ", with: "")
        // Match rgb(r,g,b) or rgba(r,g,b,a)
        guard cleaned.hasPrefix("rgb") else { return nil }
        let inner = cleaned.drop { $0 != "(" }.dropFirst().dropLast()
        let parts = inner.split(separator: ",").compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        return Color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
    }
}

// MARK: - Navigation Delegate

class WebNavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: WebViewModel?

    init(model: WebViewModel) {
        self.model = model
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.currentURL = webView.url?.absoluteString ?? ""
        model?.fetchOGMetadata()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil || !navigationAction.targetFrame!.isMainFrame {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - WebView

struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
