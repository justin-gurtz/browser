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

    var onFullscreenChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        guard let window = window else { return }
        DispatchQueue.main.async { self.repositionTrafficLights() }

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.onFullscreenChange?(true) }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in self?.onFullscreenChange?(false) }
        )
    }

    override func layout() {
        super.layout()
        repositionTrafficLights()
    }

    override func removeFromSuperview() {
        removeObservers()
        super.removeFromSuperview()
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
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
    @Binding var isFullscreen: Bool

    func makeNSView(context: Context) -> TrafficLightConfigurator {
        let view = TrafficLightConfigurator()
        view.onFullscreenChange = { fullscreen in
            isFullscreen = fullscreen
        }
        return view
    }

    func updateNSView(_ nsView: TrafficLightConfigurator, context: Context) {
        nsView.onFullscreenChange = { fullscreen in
            isFullscreen = fullscreen
        }
    }
}
