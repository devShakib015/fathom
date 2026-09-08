import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Fetches and caches the pictures an `image` element draws.
///
/// Images have to be resolved while the timeline is being built, not while the
/// view is being drawn: a widget's body is synchronous, and a `View` that
/// starts a download renders a blank box and never comes back. So the fetch
/// happens beside the JSON fetch, and the renderer only ever sees bytes it
/// already has.
///
/// Everything is downsampled on the way in. A widget extension has a hard
/// memory ceiling, and a 12-megapixel photo dropped into a 164-point box is the
/// easiest way to hit it — the extension is killed, and the widget shows the
/// system's blank placeholder with nothing to explain why.
enum ImageStore {
    /// Enough for an extra-large widget on a Retina display, and far below
    /// anything that threatens the extension's memory budget.
    static let maximumPixelSize = 1024
    /// Refuse to even decode absurd payloads.
    static let maximumDownloadBytes = 20 * 1024 * 1024

    private static var directory: URL? { SharedStore.directory("Images") }

    private static func fileName(for url: String) -> String {
        // A stable, filesystem-safe name. Not cryptographic — this only has to
        // avoid collisions between the handful of URLs one document uses.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 36) + ".png"
    }

    static func cached(_ url: String) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName(for: url)))
    }

    /// Fetches and stores one image, returning the downsampled bytes.
    /// On any failure the previously cached copy is returned instead, so a
    /// dropped connection leaves yesterday's picture rather than a hole.
    static func load(_ urlString: String, timeout: TimeInterval = 12) async -> Data? {
        guard let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http"
        else { return cached(urlString) }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("Fathom/1.0 (macOS widget)", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil
        config.urlCache = nil

        do {
            let (data, response) = try await URLSession(configuration: config).data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return cached(urlString)
            }
            guard data.count <= maximumDownloadBytes, let reduced = downsample(data) else {
                return cached(urlString)
            }
            if let directory {
                try? reduced.write(to: directory.appendingPathComponent(fileName(for: urlString)),
                                   options: .atomic)
            }
            return reduced
        } catch {
            return cached(urlString)
        }
    }

    /// Re-encodes to PNG at no more than `maximumPixelSize` on the long edge.
    /// Done through ImageIO rather than NSImage so it never has to build a
    /// full-size bitmap first, which is the part that would blow the budget.
    static func downsample(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
