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

struct OGMetadata: Equatable {
    var title: String = ""
    var description: String = ""
    var imageURL: String = ""
    var twitterTitle: String = ""
    var twitterDescription: String = ""
    var twitterImage: String = ""
    var faviconURL: String = ""
    var themeColor: String = ""
    var hasAppleTouchIcon: Bool = false
    var hasPWA: Bool = false
    var host: String = ""
}

// MARK: - WebView Model

class WebViewModel: ObservableObject {
    let webView = WKWebView()

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL = ""
    @Published var ogData = OGMetadata()
    @Published var pageBackgroundColor: Color = .white

    private var observers: [NSKeyValueObservation] = []
    private var navigationDelegate: WebNavigationDelegate?

    init() {
        let delegate = WebNavigationDelegate(model: self)
        self.navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

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
                var faviconEl = document.querySelector('link[rel="icon"]') ||
                               document.querySelector('link[rel="shortcut icon"]') ||
                               document.querySelector('link[rel="apple-touch-icon"]');
                var favicon = faviconEl ? faviconEl.getAttribute('href') || '' : '';
                if (favicon && !favicon.startsWith('http')) {
                    favicon = new URL(favicon, document.location.origin).href;
                }
                var hasAppleTouchIcon = !!document.querySelector('link[rel="apple-touch-icon"]') ||
                                       !!document.querySelector('link[rel="apple-touch-icon-precomposed"]');
                var hasPWA = !!document.querySelector('link[rel="manifest"]');
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
                    twitterTitle: getMeta('twitter:title') || getMeta('og:title') || document.title || '',
                    twitterDescription: getMeta('twitter:description') || getMeta('og:description') || getMeta('description') || '',
                    twitterImage: getMeta('twitter:image') || getMeta('og:image') || '',
                    favicon: favicon || (document.location.origin + '/favicon.ico'),
                    themeColor: getMeta('theme-color') || '',
                    hasAppleTouchIcon: hasAppleTouchIcon,
                    hasPWA: hasPWA,
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

            let metadata = OGMetadata(
                title: dict["title"] as? String ?? "",
                description: dict["description"] as? String ?? "",
                imageURL: dict["image"] as? String ?? "",
                twitterTitle: dict["twitterTitle"] as? String ?? "",
                twitterDescription: dict["twitterDescription"] as? String ?? "",
                twitterImage: dict["twitterImage"] as? String ?? "",
                faviconURL: dict["favicon"] as? String ?? "",
                themeColor: dict["themeColor"] as? String ?? "",
                hasAppleTouchIcon: dict["hasAppleTouchIcon"] as? Bool ?? false,
                hasPWA: dict["hasPWA"] as? Bool ?? false,
                host: host
            )

            // Prefetch images into URL cache so AsyncImage renders instantly
            let imageURLs = [metadata.imageURL, metadata.twitterImage, metadata.faviconURL]
                .compactMap { URL(string: $0) }
                .filter { !$0.absoluteString.isEmpty }

            let group = DispatchGroup()
            for url in imageURLs {
                group.enter()
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    group.leave()
                }.resume()
            }

            group.notify(queue: .main) {
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
            .padding(EdgeInsets(
                top: 7,
                leading: 7,
                bottom: 7,
                trailing: sidebarOpen ? 334 : 7
            ))

            if sidebarOpen {
                ogSidebar
                    .transition(.move(edge: .trailing).combined(with: .opacity))
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
            address = "https://elevenlabs.io/voice-library"
            webModel.load("https://elevenlabs.io/voice-library")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isAddressFocused = false
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
                  Text("Metadata")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
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
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
            }
            .frame(height: 40)
            .padding(.horizontal, 7)

            Divider()
                .padding(.horizontal, -7)
                .opacity(min(1, max(0, sidebarScrollOffset / 20)))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 56) {
                    ogSummary
                        .padding(.top, 12)

                  VStack(spacing: 24) {
                      ogSection("X", icon: "x-twitter") { xTwitterCard }
                      ogSection("Slack", icon: "slack") { slackCard }
                    ogSection("WhatsApp", icon: "whatsapp") { whatsAppCard }
                    ogSection("Facebook", icon: "facebook") { facebookCard }
                    ogSection("LinkedIn", icon: "linkedin") { linkedInCard }
                  }
                }
                .padding(EdgeInsets(top: 7, leading: 7, bottom: 14, trailing: 7))
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .named("sidebarScroll")).minY) { _, newValue in
                                sidebarScrollOffset = -newValue
                            }
                    }
                )
            }
            .coordinateSpace(name: "sidebarScroll")
        }
        .frame(width: 320)
        .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 7))
    }

    // MARK: - OG Summary

    private var ogSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Favicon
            if let url = URL(string: webModel.ogData.faviconURL), !webModel.ogData.faviconURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                            .cornerRadius(12)
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "globe")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.black.opacity(0.25))
                            }
                    }
                }
            }

            // Title
            Text(webModel.ogData.title.isEmpty ? "(No title)" : webModel.ogData.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)

            // Description
            Text(webModel.ogData.description.isEmpty ? "(No description)" : webModel.ogData.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

            VStack(alignment: .leading) {
              // Apple Touch Icon
              HStack(spacing: 4) {
                  Text("Apple touch icon")
                      .font(.system(size: 12))
                      .foregroundStyle(.primary.opacity(0.75))
                  Image(systemName: webModel.ogData.hasAppleTouchIcon ? "checkmark" : "xmark")
                      .font(.system(size: 10))
              }

              // Progressive Web App
              HStack(spacing: 4) {
                  Text("Progressive web app")
                      .font(.system(size: 12))
                      .foregroundStyle(.primary.opacity(0.75))
                  Image(systemName: webModel.ogData.hasPWA ? "checkmark" : "xmark")
                      .font(.system(size: 10))
              }
            }

            // Theme Color
            HStack(spacing: 6) {
              Text("Theme:")
                  .font(.system(size: 12))
              if webModel.ogData.themeColor.isEmpty {
                HStack(spacing: 4) {
                  ZStack {
                      RoundedRectangle(cornerRadius: 3)
                          .stroke(Color.black.opacity(0.5), lineWidth: 1)
                      Path { path in
                          path.move(to: CGPoint(x: 11, y: 0))
                          path.addLine(to: CGPoint(x: 0, y: 11))
                      }
                      .stroke(Color.black.opacity(0.5), lineWidth: 0.5)
                  }
                  .frame(width: 11, height: 11)
                  .clipShape(RoundedRectangle(cornerRadius: 3))
                  Text("None")
                      .font(.system(size: 12))
                      .foregroundStyle(.secondary)
                }
              } else {
                HStack(spacing: 4) {
                  RoundedRectangle(cornerRadius: 3)
                      .fill(Color(hex: webModel.ogData.themeColor) ?? .gray)
                      .frame(width: 11, height: 11)
                      .overlay(
                          RoundedRectangle(cornerRadius: 3)
                              .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
                      )
                  Text(webModel.ogData.themeColor.uppercased())
                      .font(.system(size: 11))
                      .foregroundStyle(.secondary)
                }
              }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ogSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 5) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                Text("\(title) Preview:")
                    .font(.system(size: 11, weight: .medium))
            }
            .opacity(0.8)
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

    private var xTwitterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ogImage(aspectRatio: 1.91, imageURL: twitterImage)
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

                ogImage(aspectRatio: 1.91)
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
                                            .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
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

    private func ogImage(height: CGFloat? = nil, aspectRatio: CGFloat? = nil, imageURL: String? = nil, cornerRadius: CGFloat = 10) -> some View {
        Group {
            let src = imageURL ?? webModel.ogData.imageURL
            if let url = URL(string: src), !src.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        if let aspectRatio = aspectRatio {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(aspectRatio, contentMode: .fit)
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
            TextField("Enter URL...", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isAddressFocused)
                .onSubmit {
                    isAddressFocused = false
                    webModel.load(address)
                }
                .opacity(isAddressFocused ? 1 : 0)

            if !isAddressFocused {
                Text(displayAddress.isEmpty ? "Enter URL..." : displayAddress)
                    .font(.system(size: 12))
                    .foregroundStyle(displayAddress.isEmpty ? .gray : .black)
                    .allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .modifier(HoverBackground(isActive: isAddressFocused))
        .onTapGesture { isAddressFocused = true }
    }


}

#Preview {
    ContentView()
}
