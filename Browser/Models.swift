//
//  Models.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import AppKit

// MARK: - Icon Info

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

// MARK: - Open Graph Metadata

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
    var sourceURL: String = ""
}

// MARK: - Hover Info

struct HoverInfo: Equatable {
    var type: String       // e.g. "icon", "shortcut icon", "apple-touch-icon", "og:image", "twitter:image"
    var size: String       // e.g. "(180×180)", "unknown size"
    var rawTag: String     // the raw HTML tag
    var warning: String?   // e.g. "Failed to load" shown in red with warning icon
    var image: NSImage?    // prefetched icon image
    var imageURL: String?  // URL for OG/twitter images (loaded via AsyncImage)
}
