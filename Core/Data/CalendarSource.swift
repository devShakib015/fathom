import Foundation
import EventKit

/// Calendar events and reminders.
///
/// Separate source kinds rather than more branches on `system`, because these
/// are the first data Fathom reads that belongs to the person rather than to
/// the machine. A widget that shows the weather should never cause a calendar
/// prompt, and the only way to guarantee that is to make the source something
/// you add deliberately.
enum CalendarSource {

    /// How far ahead to look. A day covers "what's next" and "what's left
    /// today", which is what a widget this size can usefully show.
    static let horizon: TimeInterval = 60 * 60 * 24
    static let maximumItems = 20

    // MARK: - Permission

    static func authorization(for entity: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: entity)
    }

    static func isAuthorised(_ entity: EKEntityType) -> Bool {
        authorization(for: entity) == .fullAccess
    }

    /// Asks once. The app calls this; the extension never does — an extension
    /// has no way to present a prompt, and a widget that silently triggered one
    /// would be worse than a widget that says it needs permission.
    @discardableResult
    static func requestAccess(to entity: EKEntityType) async -> Bool {
        let store = EKEventStore()
        do {
            return entity == .event
                ? try await store.requestFullAccessToEvents()
                : try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    // MARK: - Events

    static func events(now: Date = Date()) async -> DataValue {
        guard isAuthorised(.event) else { return denied(kind: "events") }

        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: now,
                                                 end: now.addingTimeInterval(horizon),
                                                 calendars: nil)
        let found = store.events(matching: predicate)
            .filter { !$0.isAllDay || Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(maximumItems)

        let items = found.map { event in
            DataValue.ordered([
                ("title", .string(event.title ?? "Untitled")),
                ("startsAt", .date(event.startDate)),
                ("endsAt", .date(event.endDate)),
                ("minutesUntil", .number(max(event.startDate.timeIntervalSince(now) / 60, 0))),
                ("isAllDay", .bool(event.isAllDay)),
                ("location", .string(event.location ?? "")),
                ("calendar", .string(event.calendar?.title ?? "")),
                // The calendar's own colour, so a widget can match the dot the
                // user already recognises rather than inventing one.
                ("colour", .string(hex(event.calendar?.cgColor))),
            ])
        }

        return .ordered([
            ("authorised", .bool(true)),
            ("count", .number(Double(items.count))),
            ("next", items.first ?? .null),
            ("events", .array(Array(items))),
        ])
    }

    // MARK: - Reminders

    static func reminders(now: Date = Date()) async -> DataValue {
        guard isAuthorised(.reminder) else { return denied(kind: "reminders") }

        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: now.addingTimeInterval(horizon),
            calendars: nil)

        let found = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }

        let items = found
            .sorted { ($0.dueDateComponents?.date ?? .distantFuture) < ($1.dueDateComponents?.date ?? .distantFuture) }
            .prefix(maximumItems)
            .map { reminder in
                let due = reminder.dueDateComponents?.date
                return DataValue.ordered([
                    ("title", .string(reminder.title ?? "Untitled")),
                    ("dueAt", due.map { .date($0) } ?? .null),
                    ("isOverdue", .bool(due.map { $0 < now } ?? false)),
                    ("priority", .number(Double(reminder.priority))),
                    ("list", .string(reminder.calendar?.title ?? "")),
                ])
            }

        return .ordered([
            ("authorised", .bool(true)),
            ("count", .number(Double(items.count))),
            ("next", items.first ?? .null),
            ("items", .array(Array(items))),
        ])
    }

    // MARK: - Shape when there is no permission

    /// The same shape as a successful read, with `authorised` false.
    ///
    /// A missing permission has to look different from an empty calendar: "no
    /// meetings today" and "Fathom cannot see your calendar" are opposite
    /// facts, and a widget rendering the same empty state for both is lying
    /// about one of them. `visibleWhen` on `authorised` lets a design say so.
    private static func denied(kind: String) -> DataValue {
        .ordered([
            ("authorised", .bool(false)),
            ("count", .number(0)),
            ("next", .null),
            (kind, .array([])),
        ])
    }

    private static func hex(_ color: CGColor?) -> String {
        guard let components = color?.components, components.count >= 3 else { return "" }
        return String(format: "#%02X%02X%02X",
                      Int((components[0] * 255).rounded()),
                      Int((components[1] * 255).rounded()),
                      Int((components[2] * 255).rounded()))
    }

    static var eventSchema: [(path: String, label: String)] {
        [
            ("authorised", "Fathom can see this calendar"),
            ("count", "How many events are coming up"),
            ("next.title", "The next event's name"),
            ("next.startsAt", "When it starts"),
            ("next.minutesUntil", "Minutes from now"),
            ("next.location", "Where"),
            ("next.calendar", "Which calendar"),
            ("next.colour", "That calendar's colour"),
            ("events", "All upcoming events, a list"),
            ("events[0].title", "First event's name"),
        ]
    }

    static var reminderSchema: [(path: String, label: String)] {
        [
            ("authorised", "Fathom can see your reminders"),
            ("count", "How many are due"),
            ("next.title", "The next reminder"),
            ("next.dueAt", "When it is due"),
            ("next.isOverdue", "Already past due"),
            ("next.list", "Which list"),
            ("items", "All due reminders, a list"),
            ("items[0].title", "First reminder's name"),
        ]
    }
}
