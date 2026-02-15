//
//  ContentView.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

// MARK: - Content View

struct ContentView: View {

    // MARK: Navigation State

    @StateObject var webModel = WebViewModel()
    @State var address = ""
    @FocusState var isAddressFocused: Bool
    @State var textFieldReady = false

    // MARK: Sidebar State

    @State var sidebarOpen = true
    @State var sidebarScrollOffset: CGFloat = 0

    // MARK: Sidebar Toggle Animation

    @State var webSnapshot: NSImage?
    @State var showSnapshot = false
    @State var liveWebViewWidth: CGFloat?
    @State var snapshotCoverWidth: CGFloat = 0

    // MARK: Hover Tooltip

    @State var hoveredInfo: HoverInfo?
    @State var hoveredY: CGFloat = 0
    @State var hoverDismissWork: DispatchWorkItem?
    @State var hoverAppearWork: DispatchWorkItem?

    // MARK: Layout Measurement

    @State var containerHeight: CGFloat = 0
    @State var tooltipHeight: CGFloat = 0
    @State var titleDescHeight: CGFloat = 0
    @State var iconsHeight: CGFloat = 0

    // MARK: Icon Animation

    @State var iconOpacities: [Double] = []
    @State var iconOffsets: [CGFloat] = []

    // MARK: Computed Properties

    var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var ogHost: String {
        webModel.ogData.host
    }

    var sidebarLoading: Bool {
        webModel.isLoading || webModel.ogData.sourceURL != webModel.currentURL
    }

    var displayAddress: String {
        guard let url = URL(string: webModel.currentURL),
              let host = url.host() else { return webModel.currentURL }
        var display = host
        if display.hasPrefix("www.") {
            display = String(display.dropFirst(4))
        }
        return display
    }

    var tooltipOffsetFromCenter: CGFloat {
        let edgeInset: CGFloat = 14
        let halfContainer = containerHeight / 2
        let halfTooltip = tooltipHeight / 2
        let minY: CGFloat = 7 + 41 + edgeInset + halfTooltip
        let maxY = containerHeight - 7 - edgeInset - halfTooltip
        let clampedY = min(max(hoveredY, minY), max(minY, maxY))
        return clampedY - halfContainer
    }

    // MARK: - Body

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
                .background(webModel.pageBackgroundColor)
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
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.5), lineWidth: 0.5))
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

    // MARK: - Sidebar Toggle

    func toggleSidebar() {
        let opening = !sidebarOpen
        if opening { isAddressFocused = false }
        let startWidth = webModel.webView.bounds.width
        let endWidth = max(1, startWidth + (opening ? -313 : 313))
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

    var toolbar: some View {
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

    // MARK: - URL Field

    var urlField: some View {
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
