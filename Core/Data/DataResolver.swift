import Foundation
import os

/// Everything a document needs in order to render, at one instant.
struct ResolvedData: Hashable, Sendable {
    var trees: [UUID: DataValue] = [:]
    /// Human-readable reason a source did not load, keyed by source. Shown in
    /// the editor; never shown on the widget, which falls back instead.
    var failures: [UUID: String] = [:]
    /// True when at least one value came from cache rather than the network.
    var isStale: Bool = false
    var capturedAt: Date = .distantPast

    func value(for binding: Binding) -> DataValue? {
        trees[binding.sourceID]?[path: binding.keyPath]
    }

    /// The string an element renders, whether it is bound or literal.
    func text(for element: Element) -> String {
        guard let binding = element.binding else { return element.text }
        return ValueFormatter.string(value(for: binding),
                                     format: binding.format,
                                     fallback: binding.fallback)
    }

    /// The 0…1 number an arc renders.
    func fraction(for element: Element) -> Double {
        let raw: Double? = if let binding = element.binding {
            value(for: binding)?.doubleValue
        } else {
            Double(element.text.trimmingCharacters(in: .whitespaces))
        }
        guard let raw else { return 0 }
        // Same 0…1 vs 0…100 forgiveness the percent formatter applies, so an
        // arc and the label next to it never disagree.
        let normalised = raw > 1.0001 ? raw / 100 : raw
        return min(max(normalised, 0), 1)
    }

    /// The series a sparkline renders.
    func series(for element: Element) -> [Double] {
        if element.binding != nil {
            return SeriesReader.series(from: value(for: element.binding!))
        }
        return SeriesReader.literal(element.text)
    }
}

/// Loads every source a document declares.
enum DataResolver {

    /// Timeline reloads are not a place to hang. macOS gives an extension a
    /// short window and a widget that misses it renders nothing at all, which
    /// is worse than a widget rendering slightly old numbers.
    static let requestTimeout: TimeInterval = 12

    static func resolve(_ doc: WidgetDoc, now: Date = Date()) async -> ResolvedData {
        var out = ResolvedData(capturedAt: now)

        for source in doc.sources {
            switch source.kind {
            case .system:
                out.trees[source.id] = SystemSource.snapshot(now: now)

            case .json:
                guard let string = source.url,
                      let url = URL(string: string),
                      url.scheme == "https" || url.scheme == "http"
                else {
                    out.failures[source.id] = "No valid URL"
                    if let cached = SourceCache.read(source.id) {
                        out.trees[source.id] = cached
                        out.isStale = true
                    }
                    continue
                }

                do {
                    let tree = try await fetch(url)
                    out.trees[source.id] = tree
                    SourceCache.write(tree, for: source.id)
                } catch {
                    out.failures[source.id] = error.localizedDescription
                    // Last known good beats an empty widget. A user glancing at
                    // their desktop should see yesterday's number, not a row of
                    // dashes, when the wifi dropped.
                    if let cached = SourceCache.read(source.id) {
                        out.trees[source.id] = cached
                        out.isStale = true
                    }
                }
            }
        }
        return out
    }

    static func fetch(_ url: URL) async throws -> DataValue {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        // The point of the product is freshness; a cached response would make
        // the 64-second floor meaningless.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Fathom/1.0 (macOS widget)", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.httpCookieStorage = nil
        config.urlCache = nil

        let (data, response) = try await URLSession(configuration: config).data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FetchError.status(http.statusCode)
        }
        return try DataValue.parse(data)
    }

    enum FetchError: LocalizedError {
        case status(Int)
        var errorDescription: String? {
            switch self {
            case .status(let code): "The endpoint returned \(code)."
            }
        }
    }
}

/// Last known good response per source, in the shared container so the widget
/// and the app agree about what "stale" means.
enum SourceCache {
    private static func url(_ id: UUID) -> URL? {
        AppGroup.caches?.appendingPathComponent("\(id.uuidString).json")
    }

    static func write(_ value: DataValue, for id: UUID) {
        guard let url = url(id), let data = encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read(_ id: UUID) -> DataValue? {
        guard let url = url(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? DataValue.parse(data)
    }

    /// Re-serialises the tree back to JSON. Round-tripping through the same
    /// parser on read means a cached value and a live value are indistinguish-
    /// able to everything downstream.
    private static func encode(_ value: DataValue) -> Data? {
        func plain(_ v: DataValue) -> Any {
            switch v {
            case .string(let s): s
            case .number(let n): n
            case .bool(let b): b
            case .date(let d): ISO8601DateFormatter().string(from: d)
            case .null: NSNull()
            case .array(let items): items.map(plain)
            case .object(let pairs): Dictionary(pairs.map { ($0.key, plain($0.value)) },
                                                uniquingKeysWith: { a, _ in a })
            }
        }
        return try? JSONSerialization.data(withJSONObject: plain(value), options: [.fragmentsAllowed])
    }
}
