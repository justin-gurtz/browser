//
//  WindowConfiguration.swift
//  Browser
//
//  Created by Justin Gurtz on 2/7/26.
//

import SwiftUI

// MARK: - Traffic Light Configurator

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

// MARK: - Window Configurator View

struct WindowConfiguratorView: NSViewRepresentable {
    func makeNSView(context: Context) -> TrafficLightConfigurator {
        TrafficLightConfigurator()
    }
    func updateNSView(_ nsView: TrafficLightConfigurator, context: Context) {}
}
