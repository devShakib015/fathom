import Foundation
import EventKit

/// Keeps the calendar snapshot fresh for the widget extension.
///
/// The extension cannot read the calendar — measured, see `CalendarCache` — so
/// it reads what the app last wrote. But the app only writes as a side effect
/// of resolving a document, and it never resolves the documents that live on
/// the desktop; the extension does that. Without this, a calendar widget's
/// snapshot would only ever be written when the user happened to open that
/// design in the editor, which is not a rule anyone could guess.
///
/// So: while Fathom is open, and only if some document actually asks for a
/// calendar, refresh the snapshot on a timer. Nothing is read and nothing is
/// written for a library with no calendar sources in it.
@MainActor
final class CalendarKeeper {
    static let shared = CalendarKeeper()

    private var task: Task<Void, Never>?

    /// A minute. The widget floor is sixty-four seconds, so anything faster is
    /// writing a file nobody will read before it is written again.
    private let interval: TimeInterval = 60

    private init() {}

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// Refreshes now — called when a document changes, so adding a calendar
    /// source does not leave the desktop blank for up to a minute.
    func refresh() async {
        let kinds = Set(DocumentStore.shared.allDocuments()
            .flatMap(\.sources)
            .map(\.kind)
            .filter { $0 == .calendar || $0 == .reminders })
        guard !kinds.isEmpty else { return }

        if kinds.contains(.calendar), CalendarSource.isAuthorised(.event) {
            CalendarCache.write(await CalendarSource.events(), kind: "events")
        }
        if kinds.contains(.reminders), CalendarSource.isAuthorised(.reminder) {
            CalendarCache.write(await CalendarSource.reminders(), kind: "reminders")
        }
    }
}
