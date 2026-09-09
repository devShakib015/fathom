import AppKit

/// Performs an element's action. App-side only.
///
/// Every case here is something macOS lets any application ask for, and each
/// hands the decision to the system rather than making it: a URL goes to the
/// default browser, a shortcut goes to the Shortcuts app, a path goes to
/// Finder. Fathom never executes anything itself, which is what keeps a
/// document safe to share.
@MainActor
enum ActionRunner {

    /// Returns whether anything happened, so a design bound to a name that no
    /// longer exists can say so instead of failing silently.
    @discardableResult
    static func run(_ action: Action, refresh: (() -> Void)? = nil) -> Bool {
        guard action.isSet else { return false }
        switch action.kind {
        case .none:
            return false

        case .refresh:
            refresh?()
            return true

        case .openURL:
            // Only http and https. A document is shareable, and `file://` or a
            // custom scheme in a link somebody else wrote is a way to reach
            // things a link is not supposed to reach.
            guard let url = URL(string: action.value),
                  url.scheme == "http" || url.scheme == "https" else { return false }
            return NSWorkspace.shared.open(url)

        case .openApp:
            return openApplication(named: action.value)

        case .revealPath:
            let path = (action.value as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return false }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return true

        case .runShortcut:
            // Handed to the Shortcuts app by name. Fathom does not run it, does
            // not see what it does, and cannot make it run without Shortcuts
            // agreeing.
            guard let encoded = action.value.addingPercentEncoding(
                    withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "shortcuts://run-shortcut?name=\(encoded)")
            else { return false }
            return NSWorkspace.shared.open(url)
        }
    }

    private static func openApplication(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        // A path if they gave one, otherwise the usual places. Deliberately not
        // a search of the whole disk: an app name that matches nothing should
        // do nothing rather than open whatever happened to be closest.
        let candidates = trimmed.hasPrefix("/")
            ? [trimmed]
            : ["/Applications/\(trimmed).app",
               "/System/Applications/\(trimmed).app",
               "/System/Applications/Utilities/\(trimmed).app",
               NSHomeDirectory() + "/Applications/\(trimmed).app"]

        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: configuration)
        return true
    }
}
