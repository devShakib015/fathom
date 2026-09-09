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
    /// Downsampled bytes for every image URL the document referenced, fetched
    /// alongside the data because a widget's body cannot await anything.
    var images: [String: Data] = [:]
    /// Show each element's design-time literal wherever a binding has nothing.
    ///
    /// For the catalog only. A gallery is showing you a *design*, so a CPU ring
    /// should read "43%" rather than the dash it would honestly render before a
    /// second sample exists — and rendering literals makes every thumbnail
    /// deterministic, so it can be cached once and never goes stale. Everywhere
    /// else this stays off: in the editor a wrong key path must look wrong.
    var placeholders: Bool = false
    var capturedAt: Date = .distantPast

    /// Where an element sits: nothing, or one item of a repeater.
    ///
    /// A repeater's children resolve their key paths against the *item* rather
    /// than the source root, which is what lets one child template describe
    /// every row without knowing its own index.
    struct Scope: Hashable, Sendable {
        var item: DataValue?
        var index: Int?
        var total: Int?

        static let root = Scope()
        var isRepeated: Bool { item != nil }
    }

    /// The raw value at the binding's key path, before any transform.
    func rawValue(for binding: DataBinding, scope: Scope = .root) -> DataValue? {
        let base = scope.item ?? trees[binding.sourceID]
        let path = binding.keyPath.trimmingCharacters(in: .whitespaces)
        // An empty path inside a repeater means "this item itself", which is
        // exactly what an array of plain numbers needs.
        return path.isEmpty ? base : base?[path: path]
    }

    /// What the binding actually produces: the key path's value, or the result
    /// of its expression when it has one.
    ///
    /// A transform that evaluates to null is reported as nil so the binding's
    /// `fallback` renders — an expression that cannot resolve should look
    /// exactly like a fetch that failed, because from the widget's point of
    /// view it is the same thing.
    func value(for binding: DataBinding, scope: Scope = .root) -> DataValue? {
        let own = rawValue(for: binding, scope: scope)
        guard binding.hasExpression,
              let source = binding.expression,
              let program = try? ExpressionParser.parse(source)
        else { return own }

        let result = ExpressionEvaluator(tree: trees[binding.sourceID],
                                         ownValue: own,
                                         item: scope.item,
                                         index: scope.index,
                                         total: scope.total,
                                         now: capturedAt == .distantPast ? Date() : capturedAt)
            .evaluate(program)
        return result == .null ? nil : result
    }

    /// Whether an element draws at all.
    ///
    /// Evaluated against the element's own source when it has one, so
    /// `visibleWhen` can talk about the same data the element shows without
    /// naming it twice.
    func isVisible(_ element: Element, in doc: WidgetDoc, scope: Scope = .root) -> Bool {
        guard let source = element.visibleWhen?.trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty,
              let program = try? ExpressionParser.parse(source)
        else { return true }

        let sourceID = element.binding?.sourceID ?? doc.sources.first?.id
        let tree = sourceID.flatMap { trees[$0] }
        let own = element.binding.map { rawValue(for: $0, scope: scope) } ?? scope.item

        let result = ExpressionEvaluator(tree: tree, ownValue: own,
                                         item: scope.item, index: scope.index,
                                         total: scope.total,
                                         now: capturedAt == .distantPast ? Date() : capturedAt)
            .evaluate(program)
        switch result {
        case .bool(let b): return b
        case .number(let n): return n != 0
        case .string(let s): return !s.isEmpty
        case .null: return false
        default: return true
        }
    }

    /// Every image URL this document will draw, including one per repeated
    /// row, so they can all be fetched before anything renders.
    func imageURLs(in doc: WidgetDoc) -> [String] {
        var found: [String] = []

        func walk(_ elements: [Element], scope: Scope) {
            for element in elements {
                guard isVisible(element, in: doc, scope: scope) else { continue }
                if element.kind == .image {
                    let url = text(for: element, scope: scope).trimmingCharacters(in: .whitespaces)
                    if url.hasPrefix("http"), !found.contains(url) { found.append(url) }
                }
                if element.kind == .repeater {
                    let rows = items(for: element, scope: scope)
                    let limit = min(rows.count, Element.repeaterLimit)
                    for (i, row) in rows.prefix(limit).enumerated() {
                        walk(element.children, scope: Scope(item: row, index: i, total: limit))
                    }
                } else if !element.children.isEmpty {
                    walk(element.children, scope: scope)
                }
            }
        }
        walk(doc.elements, scope: .root)
        return found
    }

    /// The items a repeater draws.
    func items(for element: Element, scope: Scope = .root) -> [DataValue] {
        guard let binding = element.binding, let resolved = value(for: binding, scope: scope) else {
            // A list layout with no data would otherwise be a blank rectangle
            // in the catalog, which says nothing about how it is laid out.
            return placeholders ? Array(repeating: .null, count: 4) : []
        }
        if case .array(let items) = resolved { return items }
        if case .object(let pairs) = resolved { return pairs.map(\.value) }
        return [resolved]
    }

    /// The string an element renders, whether it is bound or literal.
    func text(for element: Element, scope: Scope = .root) -> String {
        guard let binding = element.binding else { return element.text }
        let resolved = value(for: binding, scope: scope)
        if placeholders, resolved == nil, !element.text.isEmpty { return element.text }
        return ValueFormatter.string(resolved, format: binding.format, fallback: binding.fallback)
    }

    /// The 0…1 number an arc renders.
    func fraction(for element: Element, scope: Scope = .root) -> Double {
        let bound = element.binding.flatMap { value(for: $0, scope: scope)?.doubleValue }
        let literal = Double(element.text.trimmingCharacters(in: .whitespaces))
        let raw: Double? = element.binding == nil
            ? literal
            : (bound ?? (placeholders ? literal : nil))
        guard let raw else { return 0 }
        // Same 0…1 vs 0…100 forgiveness the percent formatter applies, so an
        // arc and the label next to it never disagree.
        let normalised = raw > 1.0001 ? raw / 100 : raw
        return min(max(normalised, 0), 1)
    }

    /// The series a sparkline renders.
    func series(for element: Element, scope: Scope = .root) -> [Double] {
        if let binding = element.binding {
            let resolved = SeriesReader.series(from: value(for: binding, scope: scope))
            if !resolved.isEmpty || !placeholders { return resolved }
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
        defer { }

        for source in doc.sources {
            switch source.kind {
            case .system:
                out.trees[source.id] = SystemSource.snapshot(now: now)

            case .calendar:
                // Read live, in the app and in the extension alike. Measured:
                // a calendar grant made to Fathom *does* reach FathomWidget.
                // See SPEC.md §6 — an earlier version of this file cached the
                // calendar into the shared store on the belief that it did not,
                // which was a misreading of trap 9.
                let tree = await CalendarSource.events(now: now)
                out.trees[source.id] = tree
                if tree[path: "authorised"] == .bool(false) {
                    out.failures[source.id] = "No calendar access — an update resets this."
                }

            case .reminders:
                let tree = await CalendarSource.reminders(now: now)
                out.trees[source.id] = tree
                if tree[path: "authorised"] == .bool(false) {
                    out.failures[source.id] = "No reminders access — an update resets this."
                }

            case .json:
                // A location-dependent endpoint is not called until there is a
                // real location to call it with. `Place.unknown` would fetch
                // perfectly valid weather for Greenwich, and a plausible wrong
                // answer is worse than a visible missing one — the user would
                // have no way to tell the widget was not about them.
                let place = PlaceStore.current
                if source.usesLocation, !place.isAuthorised {
                    out.failures[source.id] = "Needs location access"
                    continue
                }

                // Tokens resolve here rather than at edit time, so the stored
                // document stays portable and the coordinates are never written
                // into a file that might be shared.
                guard let raw = source.url,
                      case let string = DataSource.fill(raw, with: place),
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

        // Images last: their URLs can come from the data that was just fetched,
        // so there is nothing to collect until the sources have resolved.
        for url in out.imageURLs(in: doc) {
            if let bytes = await ImageStore.load(url) {
                out.images[url] = bytes
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
        SharedStore.caches?.appendingPathComponent("\(id.uuidString).json")
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
    static func encode(_ value: DataValue) -> Data? {
        DataValueJSON.data(from: value)
    }
}

/// Turns a parsed tree back into JSON. Shared, because two caches now need it
/// and a second copy would be a second set of edge cases.
/// Turns a parsed tree back into JSON. Shared, because two caches now need it
/// and a second copy would be a second set of edge cases.
///
/// Objects become dictionaries, so key order does not survive a round trip.
/// That is tolerable only because everything downstream reads by path — the
/// order matters for how a tree is *displayed*, not for what a binding finds.
enum DataValueJSON {
    static func plain(_ value: DataValue) -> Any {
        switch value {
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

    static func data(from value: DataValue) -> Data? {
        try? JSONSerialization.data(withJSONObject: plain(value), options: [.fragmentsAllowed])
    }
}

