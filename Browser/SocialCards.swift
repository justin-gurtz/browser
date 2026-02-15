//
//  SocialCards.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

// MARK: - Social Card Previews

extension ContentView {

    // MARK: Twitter Helpers

    var twitterTitle: String {
        webModel.ogData.twitterTitle.isEmpty ? webModel.ogData.title : webModel.ogData.twitterTitle
    }

    var twitterImage: String {
        webModel.ogData.twitterImage.isEmpty ? webModel.ogData.imageURL : webModel.ogData.twitterImage
    }

    var twitterImageTag: String? {
        let tag = webModel.ogData.twitterImageTag
        if !tag.isEmpty { return tag }
        let ogTag = webModel.ogData.imageTag
        if !ogTag.isEmpty { return ogTag }
        return nil
    }

    // MARK: X / Twitter Card

    var xTwitterCard: some View {
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

    // MARK: Slack Card

    var slackCard: some View {
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

    // MARK: LinkedIn Card

    var linkedInCard: some View {
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

    // MARK: Facebook Card

    var facebookCard: some View {
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

    // MARK: WhatsApp Card

    var whatsAppCard: some View {
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
}
