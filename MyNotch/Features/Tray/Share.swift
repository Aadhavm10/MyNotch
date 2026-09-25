// Adapted from NotchDrop's Share.swift (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit

enum Share {
    static func airDrop(_ urls: [URL]) {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            NSSound.beep()
            return
        }
        service.perform(withItems: urls)
    }

    /// Shows the system share menu anchored under the notch.
    static func picker(_ urls: [URL]) {
        guard let view = NotchWindowManager.shared.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let anchor = CGRect(x: view.bounds.midX - 1, y: view.bounds.maxY - 60, width: 2, height: 2)
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}
