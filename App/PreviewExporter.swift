import SwiftUI

/// Renders a document to a PNG in the shared container.
///
/// Two reasons this exists rather than being a screenshot: it will become the
/// library grid's thumbnails, and it is the only way to check what the
/// interpreter draws without photographing somebody's desktop. It runs the
/// same `WidgetCanvas` the extension runs, at the family's real point size.
@MainActor
enum PreviewExporter {

    static func png(for doc: WidgetDoc, data: ResolvedData, scale: CGFloat = 2) -> Data? {
        let size = doc.family.referenceSize
        let view = ZStack {
            // The glass material has nothing to be translucent against in an
            // offscreen render, so a preview substitutes the surface colour.
            // On the desktop the real material shows the wallpaper through.
            if doc.background.kind == .glass {
                LinearGradient(colors: [Palette.surface, Palette.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                doc.background.swatch
            }
            WidgetCanvas(doc: doc, data: data)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: size.width / 9, style: .continuous))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }
        return png
    }

    @discardableResult
    static func write(_ doc: WidgetDoc, data: ResolvedData) -> URL? {
        guard let dir = AppGroup.directory("Previews"),
              let png = png(for: doc, data: data)
        else { return nil }
        let url = dir.appendingPathComponent("\(doc.id.uuidString).png")
        try? png.write(to: url, options: .atomic)
        writeResolvedValues(doc, data: data, into: dir)
        return url
    }

    /// The numbers behind the picture, beside the picture.
    ///
    /// A render can look plausible and be wrong — an arc at 54 % and an arc at
    /// 62 % are indistinguishable by eye — so every export drops the raw and
    /// formatted value of each binding next to it.
    private static func writeResolvedValues(_ doc: WidgetDoc, data: ResolvedData, into dir: URL) {
        var rows: [[String: String]] = []
        for element in doc.elements {
            guard let binding = element.binding else { continue }
            let raw = data.value(for: binding)
            rows.append([
                "element": element.displayName,
                "kind": element.kind.rawValue,
                "keyPath": binding.keyPath,
                "raw": raw.map(\.stringValue) ?? "<missing>",
                "formatted": data.text(for: element),
                "arcFraction": element.kind == .arc ? String(format: "%.4f", data.fraction(for: element)) : "",
            ])
        }
        let payload: [String: Any] = [
            "document": doc.name,
            "capturedAt": ISO8601DateFormatter().string(from: data.capturedAt),
            "stale": data.isStale,
            "bindings": rows,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload,
                                                    options: [.prettyPrinted, .sortedKeys]) else { return }
        try? json.write(to: dir.appendingPathComponent("\(doc.id.uuidString).json"), options: .atomic)
    }
}
