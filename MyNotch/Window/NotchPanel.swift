// Window setup adapted from NotchDrop (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit
import SwiftUI

/// Borderless, transparent, non-activating panel that sits above the menu bar on every Space.
/// Fully transparent pixels let clicks fall through to whatever is underneath.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .statusBar + 8
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that reacts to the first click even though the panel is never key.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}
