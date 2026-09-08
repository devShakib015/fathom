import AppKit
import SwiftUI

/// The window an overlay lives in.
///
/// A borderless, non-activating panel. Non-activating matters more than it
/// sounds: clicking an overlay must not pull Fathom in front of whatever you
/// were working in, or the thing is an interruption rather than furniture.
final class OverlayWindow: NSPanel {

    /// Called after the user drags it, so the new position can be stored.
    var onMoved: ((CGRect) -> Void)?

    init(overlay: Overlay, content: NSView) {
        super.init(contentRect: CGRect(origin: .zero, size: overlay.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        // Seen on every Space and left alone by Mission Control, because an
        // overlay that disappears when you switch desktops is not furniture.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Excluded from screen sharing and screenshots is *not* wanted: people
        // screenshot their desktops to show them off, and the overlay is the
        // point of the picture.
        sharingType = .readOnly
        animationBehavior = .none
        contentView = content

        apply(overlay)

        NotificationCenter.default.addObserver(
            self, selector: #selector(moved), name: NSWindow.didMoveNotification, object: self)
    }

    func apply(_ overlay: Overlay) {
        level = overlay.level.windowLevel
        ignoresMouseEvents = overlay.clickThrough
        alphaValue = overlay.opacity
        setContentSize(overlay.size)
    }

    @objc private func moved() { onMoved?(frame) }

    // Never take focus. A panel that becomes key steals the caret from whatever
    // the person is actually typing in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension Overlay.Level {
    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop:
            // Above the wallpaper, below icons and windows. There is no
            // constant for this in NSWindow.Level, only in CGWindowLevel.
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        case .floating:
            .floating
        }
    }
}

/// Screen placement, in fractions rather than points.
///
/// Storing an overlay's position in points means it lands somewhere else — or
/// nowhere at all — after a resolution change, a display being unplugged, or a
/// move between a laptop screen and an external one. Fractions of the visible
/// frame survive all three.
enum OverlayPlacement {

    static func screen(for overlay: Overlay) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens.indices.contains(overlay.screenIndex)
            ? screens[overlay.screenIndex]
            : NSScreen.main ?? screens[0]
    }

    static func frame(for overlay: Overlay) -> CGRect {
        guard let screen = screen(for: overlay) else {
            return CGRect(origin: .zero, size: overlay.size)
        }
        let visible = screen.visibleFrame
        // Fractions are measured from the top-left, the way people describe
        // where something is; AppKit's origin is bottom-left.
        let x = visible.minX + visible.width * overlay.x
        let topDown = visible.height * overlay.y
        let y = visible.maxY - topDown - overlay.height

        // Never place it entirely off the screen it belongs to.
        let clampedX = min(max(x, visible.minX - overlay.width * 0.5),
                           visible.maxX - overlay.width * 0.5)
        let clampedY = min(max(y, visible.minY - overlay.height * 0.5),
                           visible.maxY - overlay.height * 0.5)
        return CGRect(x: clampedX, y: clampedY, width: overlay.width, height: overlay.height)
    }

    /// The inverse: a window frame back into stored fractions, and the index of
    /// whichever screen it now sits on.
    static func store(_ frame: CGRect, into overlay: inout Overlay) {
        let screens = NSScreen.screens
        let landed = screens.firstIndex { $0.frame.intersects(frame) } ?? overlay.screenIndex
        guard screens.indices.contains(landed) else { return }
        let visible = screens[landed].visibleFrame
        guard visible.width > 0, visible.height > 0 else { return }

        overlay.screenIndex = landed
        overlay.x = (frame.minX - visible.minX) / visible.width
        overlay.y = (visible.maxY - frame.maxY) / visible.height
    }
}
