//
//  SidebarView.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

// MARK: - Sidebar

extension ContentView {

    // MARK: OG Sidebar

    var ogSidebar: some View {
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
                    if sidebarLoading {
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

                    VStack(spacing: 0) {
                        ogSection("X Preview", icon: "x-twitter") { xTwitterCard }
                            .padding(.horizontal, 14)
                            .padding(.top, 8)
                            .padding(.bottom, 16)
                        ogSection("Slack Preview", icon: "slack") { slackCard }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                        ogSection("WhatsApp Preview", icon: "whatsapp") { whatsAppCard }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                        ogSection("Facebook Preview", icon: "facebook") { facebookCard }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
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
            .opacity(sidebarLoading ? 0.4 : 1)
        }
        .frame(width: 320)
        .padding(EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: OG Summary

    var ogSummary: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Icons + Title + Description
            VStack(alignment: .leading, spacing: 0) {
                // Animated-height container for icons
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
                            let sortedTouch = touchIcons.sorted { ($0.pixelWidth ?? 0) > ($1.pixelWidth ?? 0) }
                            let sortedFav = favicons.sorted { ($0.pixelWidth ?? 0) > ($1.pixelWidth ?? 0) }
                            FlowLayout(alignment: .bottomLeading, spacing: 14) {
                                HStack(spacing: 4) {
                                    ForEach(Array(sortedTouch.enumerated()), id: \.element.id) { idx, icon in
                                        iconTile(icon, displayAt: iconDisplaySize(icon))
                                            .opacity(idx < iconOpacities.count ? iconOpacities[idx] : 1)
                                            .offset(x: idx < iconOffsets.count ? iconOffsets[idx] : 0)
                                    }
                                }
                                if !favicons.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(sortedFav.count == 1 ? "FAVICON" : "FAVICONS")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .opacity(0.75)
                                        HStack(spacing: 4) {
                                            ForEach(Array(sortedFav.enumerated()), id: \.element.id) { idx, icon in
                                                let globalIdx = sortedTouch.count + idx
                                                iconTile(icon, displayAt: iconDisplaySize(icon))
                                                    .opacity(globalIdx < iconOpacities.count ? iconOpacities[globalIdx] : 1)
                                                    .offset(x: globalIdx < iconOffsets.count ? iconOffsets[globalIdx] : 0)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 18)
                .modifier(AnimatedHeight(height: $iconsHeight))
                .onChange(of: webModel.ogData.icons) { oldIcons, newIcons in
                    let count = newIcons.count
                    let oldCount = oldIcons.count
                    let oldTouchCount = oldIcons.filter { $0.rel.lowercased().contains("apple-touch-icon") }.count
                    let oldFavCount = oldCount - oldTouchCount
                    let newTouchCount = newIcons.filter { $0.rel.lowercased().contains("apple-touch-icon") }.count
                    let newFavCount = count - newTouchCount

                    // Icons that existed before stay visible; new ones start hidden + nudged
                    iconOpacities = (0..<count).map { i in
                        if i < newTouchCount {
                            return i < oldTouchCount ? 1.0 : 0.0
                        } else {
                            let favIdx = i - newTouchCount
                            return favIdx < oldFavCount ? 1.0 : 0.0
                        }
                    }
                    iconOffsets = (0..<count).map { i in
                        if i < newTouchCount {
                            return i < oldTouchCount ? 0 : CGFloat(-3)
                        } else {
                            let favIdx = i - newTouchCount
                            return favIdx < oldFavCount ? 0 : CGFloat(-3)
                        }
                    }
                    // Stagger animate new icons in
                    for i in 0..<count {
                        let isNewTouch = i < newTouchCount && i >= oldTouchCount
                        let isNewFav = i >= newTouchCount && (i - newTouchCount) >= oldFavCount
                        guard isNewTouch || isNewFav else { continue }
                        let staggerIdx = isNewTouch ? (i - oldTouchCount) : (i - newTouchCount - oldFavCount)
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(staggerIdx) * 0.005) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if i < iconOpacities.count { iconOpacities[i] = 1.0 }
                                if i < iconOffsets.count { iconOffsets[i] = 0 }
                            }
                        }
                    }
                }

                // Animated-height container: text swaps instantly,
                // but the height animates so content below slides.
                // Bottom padding absorbs the gap so clipping happens in empty space.
                VStack(alignment: .leading, spacing: 4) {
                    Text(webModel.ogData.title.isEmpty ? "(No title)" : webModel.ogData.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)

                    Text(webModel.ogData.description.isEmpty ? "(No description)" : webModel.ogData.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, 24)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(AnimatedHeight(height: $titleDescHeight))
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
                        metadataCell("Responsive Viewport", enabled: webModel.ogData.hasViewport)
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
                        Text("This page defines meta keywords. Not harmful, but most search engines ignore it.")
                            .frame(maxWidth: 230, alignment: .leading)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
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

    // MARK: Metadata Cells

    @ViewBuilder
    func metadataCell(_ label: String, value: String) -> some View {
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
    func metadataCell(_ label: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            if enabled {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    Text("Configured")
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
    func metadataCellTheme() -> some View {
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

    // MARK: Icon Helpers

    func iconTile(_ icon: IconInfo, displayAt: Int) -> some View {
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

    func hoverInfoForIcon(_ icon: IconInfo) -> HoverInfo {
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

    func humanizedLang(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        let locale = Locale(identifier: code)
        let language = Locale.current.localizedString(forIdentifier: code)
        if let language { return language }
        if let lang = Locale.current.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? code) {
            return lang
        }
        return code
    }

    func iconDisplaySize(_ icon: IconInfo) -> Int {
        let rel = icon.rel.lowercased()
        if rel.contains("apple-touch-icon") { return 48 }
        if rel == "shortcut icon" { return 16 }
        return 16
    }

    func parseIconSize(_ sizes: String) -> Int? {
        guard !sizes.isEmpty, sizes.lowercased() != "any" else { return nil }
        let parts = sizes.lowercased().split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]) else { return nil }
        return w
    }

    // MARK: OG Section

    func ogSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
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

    // MARK: OG Image

    func ogImage(height: CGFloat? = nil, aspectRatio: CGFloat? = nil, imageURL: String? = nil, cornerRadius: CGFloat = 10, rawTag: String? = nil, hoverType: String = "og:image") -> some View {
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

        // Use prefetched NSImage if available, otherwise fall back to AsyncImage
        let prefetched: NSImage? = {
            if src == webModel.ogData.twitterImage, let img = webModel.twitterOgImage { return img }
            if src == webModel.ogData.imageURL, let img = webModel.ogImage { return img }
            return nil
        }()

        return Group {
            if let nsImage = prefetched {
                let image = Image(nsImage: nsImage)
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
            } else if let url = URL(string: src), !src.isEmpty {
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

    func imagePlaceholder(height: CGFloat? = nil, aspectRatio: CGFloat? = nil) -> some View {
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
}
