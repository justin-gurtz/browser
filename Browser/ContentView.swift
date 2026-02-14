//
//  ContentView.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI
import WebKit
import Combine

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str.removeFirst() }
        guard str.count == 6, let int = UInt64(str, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Window Configuration

class TrafficLightConfigurator: NSView {
    private let padding: CGFloat = 7
    private let toolbarHeight: CGFloat = 40
    private var defaultXPositions: [NSWindow.ButtonType: CGFloat] = [:]

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { self.repositionTrafficLights() }
    }

    override func layout() {
        super.layout()
        repositionTrafficLights()
    }

    private func repositionTrafficLights() {
        guard let window = window else { return }
        let targetCenterY = padding + toolbarHeight / 2

        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type) else { continue }
            guard let container = button.superview else { continue }

            if defaultXPositions[type] == nil {
                defaultXPositions[type] = button.frame.origin.x
            }

            let containerHeight = container.frame.height
            let newY = containerHeight - targetCenterY - button.frame.height / 2
            let newX = (defaultXPositions[type] ?? button.frame.origin.x) + padding + 4
            button.setFrameOrigin(NSPoint(x: newX, y: newY))
        }
    }
}

struct WindowConfiguratorView: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightConfigurator {
        TrafficLightConfigurator()
    }
    func updateNSView(_ nsView: TrafficLightConfigurator, context: Context) {}
}

// MARK: - Open Graph Model

struct IconInfo: Equatable, Identifiable {
    let id = UUID()
    var url: String
    var sizes: String       // e.g. "180x180", "" if unspecified
    var rel: String         // e.g. "apple-touch-icon", "icon"
    var rawTag: String      // e.g. <link rel="icon" href="/favicon.ico">
    var image: NSImage?     // prefetched image data
    var pixelWidth: Int?    // actual image width in pixels
    var pixelHeight: Int?   // actual image height in pixels

    static func == (lhs: IconInfo, rhs: IconInfo) -> Bool {
        lhs.url == rhs.url && lhs.sizes == rhs.sizes && lhs.rel == rhs.rel && lhs.rawTag == rhs.rawTag
    }
}

struct OGMetadata: Equatable {
    var title: String = ""
    var description: String = ""
    var imageURL: String = ""
    var imageTag: String = ""
    var twitterTitle: String = ""
    var twitterDescription: String = ""
    var twitterImage: String = ""
    var twitterImageTag: String = ""
    var faviconURL: String = ""
    var icons: [IconInfo] = []
    var themeColor: String = ""
    var canonical: String = ""
    var robots: String = ""
    var keywords: String = ""
    var generator: String = ""
    var lang: String = ""
    var hasPWA: Bool = false
    var hasViewport: Bool = false
    var host: String = ""
    var imageWidth: Int?
    var imageHeight: Int?
    var twitterImageWidth: Int?
    var twitterImageHeight: Int?
}

// MARK: - WebView Model

class WebViewModel: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView = WKWebView()

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL = ""
    @Published var ogData = OGMetadata()
    @Published var pageBackgroundColor: Color = .white

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
                DispatchQueue.main.async { self?.isLoading = change.newValue ?? false }
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
                    bgColor: bgColor
                });
            })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

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
                host: host
            )

            // Prefetch OG images into URL cache and read dimensions
            let ogImageURLs = [metadata.imageURL, metadata.twitterImage, metadata.faviconURL]
                .compactMap { URL(string: $0) }
                .filter { !$0.absoluteString.isEmpty }

            var ogImageSize: (Int, Int)? = nil
            var twitterImageSize: (Int, Int)? = nil

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
                            }
                            if url.absoluteString == metadata.twitterImage && twitterImageSize == nil {
                                twitterImageSize = (w, h)
                            }
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
                metadata.icons = resolvedIcons
                if let (w, h) = ogImageSize {
                    metadata.imageWidth = w
                    metadata.imageHeight = h
                }
                if let (w, h) = twitterImageSize {
                    metadata.twitterImageWidth = w
                    metadata.twitterImageHeight = h
                }
                self?.ogData = metadata

                // Parse page background color from CSS rgb() string
                if let bgStr = dict["bgColor"] as? String {
                    self?.pageBackgroundColor = Self.parseCSS(rgb: bgStr) ?? .white
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

// MARK: - Balanced Text

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var alignment: Alignment
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { sum, row in
            sum + row.height + (sum > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { sum, row in
            sum + row.height + (sum > 0 ? spacing : 0)
        }

        var y: CGFloat
        if alignment == .bottomLeading {
            y = bounds.maxY - totalHeight
        } else {
            y = bounds.minY
        }

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let yOffset: CGFloat
                if alignment == .bottomLeading {
                    yOffset = row.height - size.height
                } else {
                    yOffset = 0
                }
                subviews[index].place(at: CGPoint(x: x, y: y + yOffset), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int]
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row(indices: [], height: 0)
        var currentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !currentRow.indices.isEmpty && currentWidth + spacing + size.width > maxWidth {
                rows.append(currentRow)
                currentRow = Row(indices: [], height: 0)
                currentWidth = 0
            }
            currentRow.indices.append(index)
            currentRow.height = max(currentRow.height, size.height)
            currentWidth += (currentRow.indices.count > 1 ? spacing : 0) + size.width
        }
        if !currentRow.indices.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

// MARK: - SVG Image View

struct SVGImageView: View {
    let url: URL
    let displaySize: Int?
    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                let size = displaySize.map { CGFloat($0) }
                if let size {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .cornerRadius(max(2, size / 6))
                } else {
                    Image(nsImage: nsImage)
                        .cornerRadius(4)
                }
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.1))
                    .frame(width: CGFloat(displaySize ?? 16), height: CGFloat(displaySize ?? 16))
            }
        }
        .onAppear { loadSVG() }
    }

    private func loadSVG() {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { nsImage = image }
        }.resume()
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        }
    }
}

// MARK: - Styles

struct HoverButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered && isEnabled ? Color.gray.opacity(0.15) : .clear)
            )
            .opacity(isEnabled ? 1.0 : 0.3)
            .onHover { isHovered = $0 }
    }
}

struct HoverBackground: ViewModifier {
    var isActive: Bool = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered || isActive ? Color.gray.opacity(0.15) : .clear)
            )
            .onHover { isHovered = $0 }
    }
}

// MARK: - Hover Info

extension String {
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        var result = self
        let entities = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
}

struct HoverInfo: Equatable {
    var type: String       // e.g. "icon", "shortcut icon", "apple-touch-icon", "og:image", "twitter:image"
    var size: String       // e.g. "(180×180)", "unknown size"
    var rawTag: String     // the raw HTML tag
    var warning: String?   // e.g. "Failed to load" shown in red with warning icon
    var image: NSImage?    // prefetched icon image
    var imageURL: String?  // URL for OG/twitter images (loaded via AsyncImage)
}


struct HoverTracker: ViewModifier {
    let info: HoverInfo
    @Binding var hoveredInfo: HoverInfo?
    @Binding var hoveredY: CGFloat
    @Binding var hoverDismissWork: DispatchWorkItem?
    @Binding var hoverAppearWork: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(
                GeometryReader { geo in
                    Color.clear
                        .onHover { hovering in
                            let fade = Animation.easeInOut(duration: 0.15)
                            if hovering {
                                hoverDismissWork?.cancel()
                                hoverDismissWork = nil
                                hoveredY = geo.frame(in: .named("mainZStack")).midY
                                // If already showing a tooltip, update immediately (moving between items)
                                if hoveredInfo != nil {
                                    hoverAppearWork?.cancel()
                                    hoverAppearWork = nil
                                    hoveredInfo = info
                                } else {
                                    hoverAppearWork?.cancel()
                                    let work = DispatchWorkItem {
                                        withAnimation(fade) {
                                            hoveredInfo = info
                                        }
                                    }
                                    hoverAppearWork = work
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                                }
                            } else {
                                hoverAppearWork?.cancel()
                                hoverAppearWork = nil
                                let work = DispatchWorkItem {
                                    withAnimation(fade) {
                                        hoveredInfo = nil
                                    }
                                }
                                hoverDismissWork = work
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                            }
                        }
                }
            )
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var webModel = WebViewModel()
    @State private var address = ""
    @State private var sidebarOpen = true
    @State private var sidebarScrollOffset: CGFloat = 0
    @State private var webSnapshot: NSImage?
    @State private var showSnapshot = false
    @State private var liveWebViewWidth: CGFloat?
    @State private var snapshotCoverWidth: CGFloat = 0
    @State private var hoveredInfo: HoverInfo?
    @State private var textFieldReady = false
    @State private var hoveredY: CGFloat = 0
    @State private var containerHeight: CGFloat = 0
    @State private var tooltipHeight: CGFloat = 0
    @State private var hoverDismissWork: DispatchWorkItem?
    @State private var hoverAppearWork: DispatchWorkItem?
    @FocusState private var isAddressFocused: Bool

    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var ogHost: String {
        webModel.ogData.host
    }

    private var displayAddress: String {
        guard let url = URL(string: webModel.currentURL),
              let host = url.host() else { return webModel.currentURL }
        var display = host
        if display.hasPrefix("www.") {
            display = String(display.dropFirst(4))
        }
        return display
    }

    private var tooltipOffsetFromCenter: CGFloat {
        let edgeInset: CGFloat = 14
        let halfContainer = containerHeight / 2
        let halfTooltip = tooltipHeight / 2
        // Top: 7px chrome + 39px toolbar + 14px inset
        let minY: CGFloat = 7 + 39 + edgeInset + halfTooltip
        // Bottom: 7px chrome + 14px inset
        let maxY = containerHeight - 7 - edgeInset - halfTooltip
        let clampedY = min(max(hoveredY, minY), max(minY, maxY))
        return clampedY - halfContainer
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                if isPreview { Spacer().frame(height: 15) }

                toolbar
                Divider()

                GeometryReader { geo in
                    WebView(webView: webModel.webView)
                        .frame(
                            width: liveWebViewWidth ?? geo.size.width,
                            height: geo.size.height,
                            alignment: .leading
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            if let snapshot = webSnapshot {
                                ZStack(alignment: .topLeading) {
                                    webModel.pageBackgroundColor
                                    Image(nsImage: snapshot).fixedSize()
                                }
                                .frame(
                                    width: max(snapshotCoverWidth, geo.size.width),
                                    height: geo.size.height,
                                    alignment: .leading
                                )
                                .opacity(showSnapshot ? 1 : 0)
                                .allowsHitTesting(false)
                            }
                        }
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 0)
            .padding(EdgeInsets(
                top: 7,
                leading: 7,
                bottom: 7,
                trailing: sidebarOpen ? 320 : 7
            ))

            if sidebarOpen {
                ogSidebar
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

        }
        .ignoresSafeArea()
        .coordinateSpace(name: "mainZStack")
        .background(GeometryReader { geo in
            Color.clear.onAppear { containerHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, h in containerHeight = h }
        })
        .overlay(alignment: .trailing) {
            if let info = hoveredInfo {
                VStack(alignment: .leading, spacing: 0) {
                    if let nsImage = info.image {
                        Image(nsImage: nsImage)
                            .interpolation(.high)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                            .padding(.bottom, 8)
                    } else if let urlStr = info.imageURL, let url = URL(string: urlStr) {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    HStack(spacing: 6) {
                        Text(info.type)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        if let warning = info.warning {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text(warning)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.red)
                        } else {
                            Text(info.size)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)
                    Text(info.rawTag.decodingHTMLEntities)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(width: 320, alignment: .leading)
                .background(Color(white: 0.95))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                .compositingGroup()
                .background(GeometryReader { geo in
                    Color.clear.onChange(of: geo.size.height) { _, h in tooltipHeight = h }
                        .onAppear { tooltipHeight = geo.size.height }
                })
                .padding(.trailing, sidebarOpen ? 334 : 21)
                .offset(y: tooltipOffsetFromCenter)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 800, minHeight: 600)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.72, blue: 0.55),
                    Color(red: 0.68, green: 0.74, blue: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(isPreview ? nil : WindowConfiguratorView())
        .onAppear {
            address = "https://www.thebrowser.company/"
            webModel.load("https://www.thebrowser.company/")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAddressFocused = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                textFieldReady = true
            }
        }
        .onChange(of: webModel.currentURL) { _, newURL in
            if !isAddressFocused {
                address = newURL
            }
        }
        .background {
            Button("") { toggleSidebar() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
        }
    }

    private func toggleSidebar() {
        let opening = !sidebarOpen
        if opening { isAddressFocused = false }
        let startWidth = webModel.webView.bounds.width
        let endWidth = max(1, startWidth + (opening ? -327 : 327))
        let coverWidth = max(startWidth, endWidth)

        webModel.takeSnapshot { [self] snapshot in
            webSnapshot = snapshot
            snapshotCoverWidth = coverWidth
            showSnapshot = true
            // Keep the live webview at the final width from frame 1.
            liveWebViewWidth = endWidth

            withAnimation(.easeInOut(duration: 0.1)) {
                sidebarOpen = opening
            }
            // Fade during the spring, after the first layout pass.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.25)) {
                    showSnapshot = false
                }
            }
            // Cleanup after spring settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                webSnapshot = nil
                snapshotCoverWidth = 0
                liveWebViewWidth = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button(action: { isAddressFocused = false; webModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .disabled(!webModel.canGoBack)

            Button(action: { isAddressFocused = false; webModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .disabled(!webModel.canGoForward)

            Button(action: {
                isAddressFocused = false
                webModel.isLoading ? webModel.stopLoading() : webModel.reload()
            }) {
                Image(systemName: webModel.isLoading ? "xmark" : "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }

            urlField

            if !sidebarOpen {
                Button(action: { toggleSidebar() }) {
                    Image(systemName: "mail.and.text.magnifyingglass")
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(HoverButtonStyle())
        .font(.system(size: 14))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .padding(.leading, 85)
        .padding(.trailing, sidebarOpen ? 6 : 10)
        .contentShape(Rectangle())
        .onTapGesture { isAddressFocused = false }
    }

    // MARK: - OG Sidebar

    private var ogSidebar: some View {
        VStack(spacing: 0) {
            if isPreview { Spacer().frame(height: 15) }

            HStack {
                HStack(spacing: 3) {
                  Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .opacity(0.75)
                  Text("Metadata Explorer")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.primary)
                    .opacity(0.75)
                if webModel.isLoading || (!displayAddress.isEmpty && displayAddress != ogHost && URL(string: webModel.currentURL)?.host() != nil) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .offset(y: 1)
                }
                }
                Spacer()
                Button(action: { toggleSidebar() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
            }
            .frame(height: 40)
            .padding(.horizontal, 14)

            Divider()
                .opacity(min(1, max(0, sidebarScrollOffset / 20)))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    ogSummary
                        .padding(.top, 12)
                        .padding(.horizontal, 14)

                  let dashedDivider = Line()
                      .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                      .foregroundStyle(Color.black.opacity(0.25))
                      .frame(height: 0.5)
                      .padding(.horizontal, 14)

                  VStack(spacing: 0) {
                      ogSection("X Preview", icon: "x-twitter") { xTwitterCard }
                          .padding(.horizontal, 14)
                          .padding(.top, 8)
                          .padding(.bottom, 16)
                      dashedDivider
                      ogSection("Slack Preview", icon: "slack") { slackCard }
                          .padding(.horizontal, 14)
                          .padding(.vertical, 16)
                      dashedDivider
                      ogSection("WhatsApp Preview", icon: "whatsapp") { whatsAppCard }
                          .padding(.horizontal, 14)
                          .padding(.vertical, 16)
                      dashedDivider
                      ogSection("Facebook Preview", icon: "facebook") { facebookCard }
                          .padding(.horizontal, 14)
                          .padding(.vertical, 16)
                      dashedDivider
                      ogSection("LinkedIn Preview", icon: "linkedin") { linkedInCard }
                          .padding(.horizontal, 14)
                          .padding(.top, 16)
                  }
                }
                .padding(EdgeInsets(top: 7, leading: 0, bottom: 14, trailing: 0))
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("sidebarScroll")).minY) { _, newValue in
                                sidebarScrollOffset = -newValue
                                if hoveredInfo != nil {
                                    hoverAppearWork?.cancel()
                                    hoverAppearWork = nil
                                    hoverDismissWork?.cancel()
                                    hoverDismissWork = nil
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        hoveredInfo = nil
                                    }
                                }
                            }
                    }
                )
            }
            .coordinateSpace(name: "sidebarScroll")
        }
        .frame(width: 320)
        .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - OG Summary

    private var ogSummary: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Icons + Title + Description
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if webModel.ogData.icons.isEmpty {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.black.opacity(0.25))
                            }
                    } else {
                        let touchIcons = webModel.ogData.icons.filter { $0.rel.lowercased().contains("apple-touch-icon") }
                        let favicons = webModel.ogData.icons.filter { !$0.rel.lowercased().contains("apple-touch-icon") }

                        VStack(alignment: .leading, spacing: 6) {
                            if !touchIcons.isEmpty {
                                Text(touchIcons.count == 1 ? "APPLE TOUCH ICON" : "APPLE TOUCH ICONS")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .opacity(0.75)
                            }
                            FlowLayout(alignment: .bottomLeading, spacing: 14) {
                                HStack(spacing: 4) {
                                    ForEach(touchIcons.sorted { a, b in
                                        (a.pixelWidth ?? 0) > (b.pixelWidth ?? 0)
                                    }) { icon in
                                        iconTile(icon, displayAt: iconDisplaySize(icon))
                                    }
                                }
                                if !favicons.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(favicons.count == 1 ? "FAVICON" : "FAVICONS")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .opacity(0.75)
                                        HStack(spacing: 4) {
                                            ForEach(favicons.sorted { a, b in
                                                (a.pixelWidth ?? 0) > (b.pixelWidth ?? 0)
                                            }) { icon in
                                                iconTile(icon, displayAt: iconDisplaySize(icon))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(webModel.ogData.title.isEmpty ? "(No title)" : webModel.ogData.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(webModel.ogData.description.isEmpty ? "(No description)" : webModel.ogData.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                }
            }

            // Metadata table
            let gridDivider = Color.black.opacity(0.12)
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    // Row 1: Theme / Generator
                    HStack(spacing: 0) {
                        metadataCellTheme()
                        gridDivider.frame(width: 0.5)
                        metadataCell("Generator", value: webModel.ogData.generator)
                    }
                    .frame(minHeight: 48)
                    gridDivider.frame(height: 0.5)
                    // Row 2: Mobile / Language
                    HStack(spacing: 0) {
                        metadataCell("Mobile", enabled: webModel.ogData.hasViewport)
                        gridDivider.frame(width: 0.5)
                        metadataCell("Language", value: humanizedLang(webModel.ogData.lang))
                    }
                    .frame(minHeight: 48)
                    gridDivider.frame(height: 0.5)
                    // Row 3: Robots / PWA
                    HStack(spacing: 0) {
                        metadataCell("Robots", value: webModel.ogData.robots)
                        gridDivider.frame(width: 0.5)
                        metadataCell("PWA", enabled: webModel.ogData.hasPWA)
                    }
                    .frame(minHeight: 48)
                    gridDivider.frame(height: 0.5)
                    // Row 4: Canonical (full width)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CANONICAL")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(webModel.ogData.canonical.isEmpty ? "—" : webModel.ogData.canonical)
                            .font(.system(size: 11))
                            .foregroundStyle(webModel.ogData.canonical.isEmpty ? .tertiary : .primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }
                .background(Color.black.opacity(0.04))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(gridDivider, lineWidth: 0.5))

                if !webModel.ogData.keywords.isEmpty {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        (Text("Note: ").font(.system(size: 10, weight: .semibold)) + Text("This page defines meta keywords. Not harmful, but most search engines ignore it.").font(.system(size: 10)))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 260, alignment: .leading)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(Color.black.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(gridDivider, lineWidth: 0.5))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadataCell(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 11))
                .foregroundStyle(value.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadataCell(_ label: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            if enabled {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("Enabled")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.75, green: 1.0, blue: 0.78))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(red: 0.3, green: 0.65, blue: 0.35))
                .clipShape(Capsule())
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func metadataCellTheme() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("THEME")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            if webModel.ogData.themeColor.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: webModel.ogData.themeColor) ?? .gray)
                        .frame(width: 11, height: 11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                        )
                    Text(webModel.ogData.themeColor.uppercased())
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconRow(_ icon: IconInfo) -> some View {
        let parsedSize = parseIconSize(icon.sizes)
        let displaySize = parsedSize.map { min($0, 128) }
        let isSVG = icon.url.lowercased().hasSuffix(".svg") || icon.rawTag.lowercased().contains("image/svg")

        return HStack(alignment: .top, spacing: 10) {
            if let url = URL(string: icon.url) {
                if isSVG {
                    SVGImageView(url: url, displaySize: displaySize)
                } else {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            if let size = displaySize {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: CGFloat(size), height: CGFloat(size))
                                    .cornerRadius(CGFloat(max(2, size / 6)))
                            } else {
                                image
                                    .cornerRadius(4)
                            }
                        default:
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.1))
                                .frame(width: CGFloat(displaySize ?? 16), height: CGFloat(displaySize ?? 16))
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(icon.rel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(icon.sizes.isEmpty ? "intrinsic" : icon.sizes)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .modifier(HoverTracker(info: hoverInfoForIcon(icon), hoveredInfo: $hoveredInfo, hoveredY: $hoveredY, hoverDismissWork: $hoverDismissWork, hoverAppearWork: $hoverAppearWork))
    }

    private func iconTile(_ icon: IconInfo, displayAt: Int) -> some View {
        let size = CGFloat(displayAt)

        return Group {
            if let nsImage = icon.image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .cornerRadius(max(2, size / 6))
            } else {
                RoundedRectangle(cornerRadius: max(2, size / 6))
                    .fill(Color.black.opacity(0.1))
                    .frame(width: size, height: size)
            }
        }
        .modifier(HoverTracker(info: hoverInfoForIcon(icon), hoveredInfo: $hoveredInfo, hoveredY: $hoveredY, hoverDismissWork: $hoverDismissWork, hoverAppearWork: $hoverAppearWork))
    }

    private func hoverInfoForIcon(_ icon: IconInfo) -> HoverInfo {
        let rel = icon.rel.lowercased()
        let type: String
        if rel.contains("apple-touch-icon") {
            type = "Apple Touch Icon"
        } else if rel == "shortcut icon" {
            type = "Shortcut Icon"
        } else {
            type = "Icon"
        }
        let size: String
        let warning: String?
        if let w = icon.pixelWidth, let h = icon.pixelHeight {
            size = "\(w)×\(h)"
            warning = nil
        } else if icon.image == nil {
            size = ""
            warning = "Failed to load"
        } else {
            size = "unknown size"
            warning = nil
        }
        return HoverInfo(type: type, size: size, rawTag: icon.rawTag, warning: warning, image: icon.image)
    }

    private func humanizedLang(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        let locale = Locale(identifier: code)
        let language = Locale.current.localizedString(forIdentifier: code)
        if let language { return language }
        if let lang = Locale.current.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? code) {
            return lang
        }
        return code
    }

    private func iconDisplaySize(_ icon: IconInfo) -> Int {
        let rel = icon.rel.lowercased()
        if rel.contains("apple-touch-icon") { return 48 }
        if rel == "shortcut icon" { return 16 }
        return 16
    }

    private func parseIconSize(_ sizes: String) -> Int? {
        guard !sizes.isEmpty, sizes.lowercased() != "any" else { return nil }
        let parts = sizes.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]) else { return nil }
        return w
    }

    private func ogSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.8)
                Spacer()
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .opacity(0.25)
            }
            .padding(.top, -5)
            content()
        }
    }

    // MARK: - X / Twitter Card

    private var twitterTitle: String {
        webModel.ogData.twitterTitle.isEmpty ? webModel.ogData.title : webModel.ogData.twitterTitle
    }

    private var twitterImage: String {
        webModel.ogData.twitterImage.isEmpty ? webModel.ogData.imageURL : webModel.ogData.twitterImage
    }

    private var twitterImageTag: String? {
        let tag = webModel.ogData.twitterImageTag
        if !tag.isEmpty { return tag }
        let ogTag = webModel.ogData.imageTag
        if !ogTag.isEmpty { return ogTag }
        return nil
    }

    private var xTwitterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ogImage(aspectRatio: 1.91, imageURL: twitterImage, rawTag: twitterImageTag, hoverType: webModel.ogData.twitterImageTag.isEmpty ? "og:image" : "twitter:image")
                .overlay(alignment: .bottomLeading) {
                    if !twitterTitle.isEmpty {
                        Text(twitterTitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black.opacity(0.4))
                            )
                            .padding(8)
                    }
                }

            Text(ogHost.isEmpty ? "example.com" : ogHost)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.top, 5)
        }
    }

    // MARK: - Slack Card

    private var slackCard: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.black.opacity(0.15))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    if let url = URL(string: webModel.ogData.faviconURL), !webModel.ogData.faviconURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 14, height: 14)
                            default:
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Text(ogHost.isEmpty ? "example.com" : ogHost)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if !webModel.ogData.title.isEmpty {
                    Text(webModel.ogData.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0x12/255.0, green: 0x63/255.0, blue: 0xA3/255.0))
                        .lineLimit(1)
                }

                if !webModel.ogData.description.isEmpty {
                    Text(webModel.ogData.description)
                        .font(.system(size: 11))
                        .foregroundStyle(.black.opacity(0.8))
                        .lineLimit(3)
                }

                ogImage(aspectRatio: 1.91, imageURL: twitterImage, rawTag: twitterImageTag, hoverType: webModel.ogData.twitterImageTag.isEmpty ? "og:image" : "twitter:image")
            }
            .padding(.leading, 8)
        }
    }

    // MARK: - LinkedIn Card

    private var linkedInCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ogImage(aspectRatio: 1.91, cornerRadius: 0)

            VStack(alignment: .leading, spacing: 4) {
                if !webModel.ogData.title.isEmpty {
                    Text(webModel.ogData.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                        .lineLimit(2)
                }

                HStack(spacing: 0) {
                    Text(ogHost.isEmpty ? "example.com" : ogHost)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(" • 1 min read")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#f2f6f8") ?? .gray.opacity(0.05))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Facebook Card

    private var facebookCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ogImage(aspectRatio: 1.91, cornerRadius: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(ogHost.isEmpty ? "example.com" : ogHost)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !webModel.ogData.title.isEmpty {
                    Text(webModel.ogData.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#f8f9fb") ?? .gray.opacity(0.05))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - WhatsApp Card

    private var whatsAppCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ogImage(aspectRatio: 1.91, cornerRadius: 0)

            VStack(alignment: .leading, spacing: 16) {
                    if !webModel.ogData.title.isEmpty && !webModel.ogData.description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !webModel.ogData.title.isEmpty {
                        Text(webModel.ogData.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .lineLimit(2)
                    }

                    if !webModel.ogData.description.isEmpty {
                        Text(webModel.ogData.description)
                            .font(.system(size: 12))
                            .foregroundStyle(.black.opacity(0.5))
                            .lineSpacing(3)
                    }
                }
                    }

                HStack(spacing: 5) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)

                    Text(ogHost.isEmpty ? "example.com" : ogHost)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if let url = URL(string: webModel.ogData.faviconURL), !webModel.ogData.faviconURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.25), lineWidth: 0.5)
                                    )
                            default:
                                Image(systemName: "globe")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "#d5f3cf") ?? .green.opacity(0.15))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Placeholder Card

    private var ogPlaceholderCard: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.15))
            .frame(height: 100)
            .overlay {
                Text("Coming soon")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
    }

    // MARK: - OG Image

    private func ogImage(height: CGFloat? = nil, aspectRatio: CGFloat? = nil, imageURL: String? = nil, cornerRadius: CGFloat = 10, rawTag: String? = nil, hoverType: String = "og:image") -> some View {
        let src = imageURL ?? webModel.ogData.imageURL
        let tag = rawTag ?? webModel.ogData.imageTag
        let info: HoverInfo = {
            if tag.isEmpty && src.isEmpty {
                return HoverInfo(type: hoverType, size: "", rawTag: "Not defined")
            }
            let rawTagDisplay = tag.isEmpty ? src : tag
            if let url = URL(string: src), url.scheme?.hasPrefix("http") == true, url.host() != nil {
                // Look up prefetched dimensions
                let size: String
                if src == webModel.ogData.twitterImage,
                   let w = webModel.ogData.twitterImageWidth, let h = webModel.ogData.twitterImageHeight {
                    size = "\(w)×\(h)"
                } else if let w = webModel.ogData.imageWidth, let h = webModel.ogData.imageHeight,
                          (src == webModel.ogData.imageURL || imageURL == nil) {
                    size = "\(w)×\(h)"
                } else {
                    size = "unknown size"
                }
                return HoverInfo(type: hoverType, size: size, rawTag: rawTagDisplay, imageURL: url.absoluteString)
            }
            return HoverInfo(type: hoverType, size: "", rawTag: rawTagDisplay, warning: "Malformed URL")
        }()

        return Group {
            if let url = URL(string: src), !src.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        if let aspectRatio = aspectRatio {
                            Color.clear
                                .aspectRatio(aspectRatio, contentMode: .fit)
                                .overlay(
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                )
                                .clipped()
                        } else {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: height ?? 120)
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                    default:
                        imagePlaceholder(height: height ?? (aspectRatio != nil ? nil : 120), aspectRatio: aspectRatio)
                    }
                }
            } else {
                imagePlaceholder(height: height ?? (aspectRatio != nil ? nil : 120), aspectRatio: aspectRatio)
            }
        }
        .background(Color.white)
        .cornerRadius(cornerRadius)
        .modifier(HoverTracker(info: info, hoveredInfo: $hoveredInfo, hoveredY: $hoveredY, hoverDismissWork: $hoverDismissWork, hoverAppearWork: $hoverAppearWork))
    }

    private func imagePlaceholder(height: CGFloat? = nil, aspectRatio: CGFloat? = nil) -> some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(height: height)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 24))
                    .foregroundStyle(.gray.opacity(0.4))
            }
    }

    // MARK: - URL Field

    private var urlField: some View {
        ZStack(alignment: .leading) {
            if textFieldReady {
                TextField("Enter URL...", text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isAddressFocused)
                    .disableAutocorrection(true)
                    .textContentType(nil)
                    .onSubmit {
                        isAddressFocused = false
                        webModel.load(address)
                    }
                    .opacity(isAddressFocused ? 1 : 0)
            }

            if !isAddressFocused {
                Text(displayAddress.isEmpty ? "Enter URL..." : displayAddress)
                    .font(.system(size: 12))
                    .foregroundStyle(displayAddress.isEmpty ? .gray : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .modifier(HoverBackground(isActive: isAddressFocused))
        .onTapGesture { isAddressFocused = true }
    }


}

#Preview {
    ContentView()
}
