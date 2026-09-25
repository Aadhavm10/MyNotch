// Adapted from NotchDrop (https://github.com/Lakr233/NotchDrop), MIT License, Copyright (c) 2024 Lakr Aream.

import AppKit

extension NSScreen {
    /// Size of the physical camera notch, or `.zero` when the screen has none.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else { return .zero }
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        guard leftPadding > 0, rightPadding > 0 else { return .zero }
        return CGSize(width: frame.width - leftPadding - rightPadding, height: safeAreaInsets.top)
    }

    var hasNotch: Bool { notchSize != .zero }

    /// Height of the menu bar on this screen (used for fake notches).
    var menuBarHeight: CGFloat {
        let height = frame.maxY - visibleFrame.maxY
        return height > 0 ? height : 24
    }

    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        guard let displayID else { return false }
        return CGDisplayIsBuiltin(displayID) == 1
    }

    static var builtIn: NSScreen? { screens.first { $0.isBuiltIn } }
}
