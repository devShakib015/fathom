import AppKit
import SwiftUI
import Observation

/// Renders a document into the desktop picture, and can give the old one back.
@MainActor
@Observable
final class WallpaperController {
    private(set) var wallpaper: Wallpaper?
    private(set) var lastError: String?
    private(set) var lastWrittenAt: Date?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Two filenames, used alternately.
    ///
    /// macOS caches the desktop picture by URL: write new bytes to the same
    /// path and the screen does not change, with no error and no clue. So each
    /// rewrite lands on the other name and the swap is always a new URL. Two
    /// rather than a timestamp so the directory cannot grow without bound.
    @ObservationIgnored private var flip = false

    init() { wallpaper = WallpaperStore.shared.load() }

    func start() { if wallpaper?.isEnabled == true { begin() } }

    // MARK: - Editing

    func set(_ wallpaper: Wallpaper?) {
        let previous = self.wallpaper
        self.wallpaper = wallpaper
        WallpaperStore.shared.save(wallpaper)
        task?.cancel(); task = nil

        if wallpaper?.isEnabled == true {
            begin()
        } else if previous != nil {
            // Turning it off puts the user's own picture back. Anything else
            // leaves them with a Fathom render they cannot easily undo.
            restore()
        }
    }

    func use(_ doc: WidgetDoc) { set(Wallpaper(documentID: doc.id)) }

    /// Holds a candidate in memory so it can be previewed without being saved
    /// or applied. Nothing is written and the desktop is not touched.
    func stage(_ doc: WidgetDoc) {
        if wallpaper?.documentID != doc.id {
            var candidate = Wallpaper(documentID: doc.id)
            candidate.isEnabled = false
            wallpaper = candidate
        }
    }

    func clear() { set(nil) }

    func documentChanged(_ documentID: UUID) {
        guard wallpaper?.documentID == documentID, wallpaper?.isEnabled == true else { return }
        Task { await render() }
    }

    /// Puts back whatever was there before Fathom first changed it.
    func restore() {
        guard let screen = targetScreen() else { return }
        guard let original = WallpaperStore.shared.original() else {
            lastError = "Your previous wallpaper is not on disk any more, so it cannot be put back. Choose one in System Settings ▸ Wallpaper."
            return
        }
        do {
            try NSWorkspace.shared.setDesktopImageURL(original, for: screen, options: [:])
            WallpaperStore.shared.forgetOriginal()
            lastError = nil
        } catch {
            lastError = "Could not put your wallpaper back: \(error.localizedDescription)"
        }
    }

    var hasOriginal: Bool { WallpaperStore.shared.original() != nil }

    /// Whether the wallpaper currently on screen could be put back.
    ///
    /// False when macOS is displaying an image whose file has been deleted,
    /// which it will happily keep doing. Checked *before* anything is changed,
    /// because "I can undo this" is only worth saying in advance.
    var canRestoreCurrent: Bool {
        // A good original already in hand settles it.
        if hasOriginal { return true }

        guard let screen = targetScreen(),
              let current = NSWorkspace.shared.desktopImageURL(for: screen) else { return false }

        // On screen is one of ours and no original is held — which happens when
        // the original's file had already been deleted, so it was never
        // recorded. There is nothing to go back to, and saying otherwise is the
        // same false promise this whole check exists to stop.
        if current.path.hasPrefix(SharedStore.root.path) { return false }

        return FileManager.default.fileExists(atPath: current.path)
    }

    // MARK: - Rendering

    private func begin() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.render()
                let seconds = self?.wallpaper?.refresh ?? Wallpaper.defaultRefresh
                try? await Task.sleep(for: .seconds(max(seconds, Wallpaper.refreshFloor)))
            }
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard let wallpaper else { return NSScreen.main }
        return screens.indices.contains(wallpaper.screenIndex)
            ? screens[wallpaper.screenIndex] : (NSScreen.main ?? screens.first)
    }

    /// Renders to a file and returns it, without touching the desktop.
    ///
    /// Separate from applying on purpose. Replacing somebody's desktop picture
    /// is a change to their machine that they should get to look at first —
    /// especially since a dynamic desktop cannot be restored byte for byte, so
    /// "undo" is a promise this can only mostly keep.
    @discardableResult
    func preview() async -> URL? {
        guard let wallpaper,
              let doc = DocumentStore.shared.document(id: wallpaper.documentID),
              let screen = targetScreen(),
              let dir = SharedStore.directory("Wallpaper")
        else { return nil }

        let data = await DataResolver.resolve(doc)
        guard let png = image(doc: doc, data: data, wallpaper: wallpaper, screen: screen) else {
            lastError = "Could not render the wallpaper."
            return nil
        }
        let url = dir.appendingPathComponent("preview.png")
        try? png.write(to: url, options: .atomic)
        lastError = nil
        return url
    }

    func render() async {
        guard let wallpaper, wallpaper.isEnabled,
              let doc = DocumentStore.shared.document(id: wallpaper.documentID),
              let screen = targetScreen(),
              let dir = SharedStore.directory("Wallpaper")
        else { return }

        let data = await DataResolver.resolve(doc)
        guard let png = image(doc: doc, data: data, wallpaper: wallpaper, screen: screen) else {
            lastError = "Could not render the wallpaper."
            return
        }

        // Remember what was there, once, before the first change — and only
        // when it is a file that still exists. See WallpaperStore.
        if let current = NSWorkspace.shared.desktopImageURL(for: screen),
           !current.path.hasPrefix(SharedStore.root.path) {
            WallpaperStore.shared.rememberOriginal(current)
        }

        flip.toggle()
        let url = dir.appendingPathComponent(flip ? "a.png" : "b.png")
        do {
            try png.write(to: url, options: .atomic)
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            lastWrittenAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The screen-sized picture: the document, drawn large, over a backdrop
    /// that fills everything it does not.
    private func image(doc: WidgetDoc, data: ResolvedData,
                       wallpaper: Wallpaper, screen: NSScreen) -> Data? {
        let points = screen.frame.size
        let card = doc.family.referenceSize
        let size = CGSize(width: card.width * wallpaper.scale,
                          height: card.height * wallpaper.scale)
        let place = wallpaper.position.alignment

        let view = ZStack {
            if wallpaper.extendsBackdrop {
                doc.background.swatch
            } else {
                Color.black
            }
            ZStack {
                doc.background.swatch
                WidgetCanvas(doc: doc, data: data)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(
                cornerRadius: WidgetDoc.Family.cornerRadius * wallpaper.scale,
                style: .continuous))
            .position(x: points.width * place.x, y: points.height * place.y)
        }
        .frame(width: points.width, height: points.height)
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        // The screen's own backing scale, so a Retina desktop is not upscaled
        // from a half-resolution render.
        renderer.scale = screen.backingScaleFactor
        renderer.isOpaque = true

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }
}
