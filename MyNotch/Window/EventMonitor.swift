// Adapted from NotchDrop (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit

/// Wraps a global + local NSEvent monitor for the same mask.
final class EventMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit { stop() }

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handler(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
