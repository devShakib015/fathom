import Foundation

/// A log the widget extension can always write, even when everything else has
/// failed.
///
/// The unified log is not readable on every machine — `log show` returns
/// nothing here — and a widget extension has no console, no debugger worth
/// trusting, and no UI beyond the widget face. But a sandboxed
/// extension can always write to its *own* container, and that container is
/// plain to read from a shell. This is the probe's trick, reused: when the
/// thing you are measuring cannot talk, give it a file.
///
/// Deliberately not conditional on DEBUG. The build that ships is the build
/// that has to be diagnosable, and a handful of lines per reload costs
/// nothing next to being unable to answer "did it even run?".
enum ExtensionTrace {
    /// Not `~/Library/Logs`. Inside a sandboxed extension that path is
    /// restricted even though it sits within the extension's own container —
    /// the probe only got away with it because it carried a
    /// `temporary-exception.files.home-relative-path.read-write` entitlement
    /// naming that exact directory. Application Support needs no exception.
    private static let url: URL? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Fathom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("extension.log")
    }()

    private static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func write(_ message: String) {
        guard let url, let data = "\(stamp.string(from: Date()))\t\(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    /// Where that file actually lands, so the app can tell you where to look.
    static var path: String { url?.path ?? "unavailable" }
}

/// What the store can see, as a value rather than a log line.
///
/// The widget renders this when it has nothing to draw, which turns an
/// otherwise silent failure — an ad-hoc signature strips the App Group
/// entitlement and
/// every widget renders blank forever — into something legible from across
/// the room.
struct StoreDiagnosis: Hashable, Sendable {
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` returned a path.
    var urlResolves: Bool
    /// The directory could actually be listed. This is the one that matters:
    /// an ad-hoc signed extension resolves the URL and is then denied the
    /// directory, so a check that stops at `urlResolves` reports success while
    /// every widget renders its fallbacks.
    var readable: Bool
    var writable: Bool
    var documentCount: Int
    var familiesPresent: [String]
    var containerPath: String

    static func current() -> StoreDiagnosis {
        guard let container = SharedStore.container else {
            return StoreDiagnosis(urlResolves: false, readable: false, writable: false,
                                  documentCount: 0, familiesPresent: [],
                                  containerPath: "unresolved")
        }

        let fm = FileManager.default
        let readable = (try? fm.contentsOfDirectory(atPath: container.path)) != nil

        // Probe the write rather than infer it. The sandbox can hand back a
        // resolvable URL it will not let you touch, and the difference is the
        // entire failure.
        let probe = container.appendingPathComponent(".fathom-write-probe")
        let writable = (try? Data().write(to: probe)) != nil
        try? fm.removeItem(at: probe)

        let docs = DocumentStore.shared.allDocuments()
        return StoreDiagnosis(urlResolves: true,
                              readable: readable,
                              writable: writable,
                              documentCount: docs.count,
                              familiesPresent: docs.map(\.family.rawValue).sorted(),
                              containerPath: container.path)
    }

    /// True only when the shared container is genuinely usable.
    var usable: Bool { urlResolves && readable }

    var summary: String {
        guard urlResolves else { return "container URL unresolved" }
        guard readable else { return "container DENIED (url ok, cannot read)" }
        return "container ok r\(writable ? "w" : "o"), \(documentCount) docs [\(familiesPresent.joined(separator: ","))]"
    }

    /// One line for a person looking at a widget, not a log.
    var headline: String {
        if !urlResolves { return "The App Group entitlement is missing from this build." }
        if !readable { return "This build is signed ad hoc, so macOS denies the extension its shared storage." }
        return "Design one in Fathom and it appears here."
    }
}
