import Foundation
import os

/// The one place the app and the widget extension both read and write.
///
/// **This is deliberately not an App Group, and that took measuring.**
///
/// Trap 3 says a sandboxed extension's `homeDirectoryForCurrentUser` is its own
/// container, so a home-relative exception can never reach the app's files, and
/// concludes an App Group is the only mechanism. That is true, but only for a
/// build signed by a real team. An App Group is bound to the signing team, and
/// an ad-hoc signature has no team — so for an ad-hoc build macOS *resolves*
/// the group URL for the extension and then denies it the directory.
///
/// Measured 8 September 2026, identical binary, two signatures:
///
///     Development signed (TeamIdentifier=VKN4MYB5ZW)  container ok rw, 2 docs
///     ad-hoc signed      (TeamIdentifier not set)     url ok, cannot read
///
/// The app survives ad-hoc signing; the extension does not. Since Fathom ships
/// unsigned on GitHub Releases, an App Group would mean every downloaded copy
/// showed empty widgets forever, with the URL resolving and nothing logging an
/// error. A fixed absolute path reached through a sandbox exception is not
/// bound to any signing identity, so it works under both.
enum SharedStore {
    static let log = Logger(subsystem: "com.devshakib.fathom", category: "store")

    /// Scoped by uid so that two people using the same Mac do not share, or
    /// overwrite, each other's widgets. The sandbox exception is declared on
    /// the parent directory, which covers everything beneath it.
    static let root: URL = URL(fileURLWithPath: "/Users/Shared/Fathom/\(getuid())", isDirectory: true)

    /// nil means the shared directory could not be created or read, which is
    /// the one failure that leaves every widget on the machine blank. Callers
    /// surface it rather than swallowing it.
    static var container: URL? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            // Readable and writable by this user only. /Users/Shared is world
            // writable by design, and a widget document can name an endpoint,
            // so the contents should not be another account's business.
            try? fm.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        return (try? fm.contentsOfDirectory(atPath: root.path)) != nil ? root : nil
    }

    static func directory(_ name: String) -> URL? {
        guard let container else { return nil }
        let url = container.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var documents: URL? { directory("Documents") }
    static var caches: URL? { directory("Caches") }

    static var diagnosis: String { container?.path ?? "Unavailable — \(root.path) is not readable." }
}
