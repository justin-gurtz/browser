//
//  Components.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

// MARK: - Animated Height Modifier

/// Measures the content's natural height and exposes it via a binding.
/// The parent animates the binding; this modifier applies it as a frame + clip.
struct AnimatedHeight: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: HeightPrefKey.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(HeightPrefKey.self) { newH in
                if height == 0 {
                    // First measurement — set immediately, no animation
                    height = newH
                } else if newH != height {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        height = newH
                    }
                }
            }
            .frame(height: height, alignment: .topLeading)
            .clipped()
    }

    private struct HeightPrefKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

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

// MARK: - Hover Tracker

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
