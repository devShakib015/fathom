import Foundation

/// The calendar, as last read by the app, for the extension to draw.
///
/// Exists because of a measurement, not a preference. A calendar grant made to
/// Fathom does **not** reach `FathomWidget`: the app's own tree browser
/// reported `authorised: true` while, minutes later and on the same Mac, the
/// extension rendered `Auth=false Count=0`. The two are separate TCC subjects,
/// and the extension has no way to ask for anything — it has no window, and a
/// widget that silently raised a permission prompt would be worse than one that
/// admits it cannot see your diary.
///
/// So the shape is the same as `Place`, for the same reason: **the app reads
/// and writes, the extension only ever reads.** That is now the rule for every
/// permission-shaped source in this project rather than a special case for
/// location.
///
/// Two consequences worth being honest about:
///
/// * A widget is only as fresh as the last time the app ran. The snapshot
///   carries its own timestamp so a design can say how old it is, and the app
///   refreshes on launch and while it is open.
/// * **Event titles are written to disk**, in the shared container at
///   `/Users/Shared/Fathom/<uid>`, which is created 0700 and readable only by
///   this user. It is the same directory the documents live in. This is a real
///   trade and it is made deliberately: the alternative is not a more private
///   calendar widget, it is a calendar widget that never works.
enum CalendarCache {
    private static func url(for kind: String) -> URL? {
        SharedStore.directory("Calendar")?.appendingPathComponent("\(kind).json")
    }

    static func write(_ value: DataValue, kind: String) {
        // The timestamp travels beside the tree rather than inside it, so the
        // cached shape a widget binds to is exactly the live shape.
        let wrapper: [String: Any] = [
            "takenAt": ISO8601DateFormatter().string(from: Date()),
            "tree": DataValueJSON.plain(value),
        ]
        guard let url = url(for: kind),
              let data = try? JSONSerialization.data(withJSONObject: wrapper) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The last snapshot, with `authorised` exactly as the app recorded it and
    /// two fields added so a design can say how old the answer is.
    static func read(kind: String) -> DataValue? {
        guard let url = url(for: kind), let data = try? Data(contentsOf: url),
              let wrapper = try? DataValue.parse(data),
              case .object(let outer) = wrapper,
              let tree = outer.first(where: { $0.key == "tree" })?.value,
              case .object(let pairs) = tree
        else { return nil }

        let takenAt: Date
        if case .date(let d)? = outer.first(where: { $0.key == "takenAt" })?.value {
            takenAt = d
        } else if case .string(let s)? = outer.first(where: { $0.key == "takenAt" })?.value,
                  let d = ISO8601DateFormatter().date(from: s) {
            takenAt = d
        } else {
            takenAt = .distantPast
        }

        return .object(pairs + [
            (key: "ageMinutes", value: .number(Date().timeIntervalSince(takenAt) / 60)),
            (key: "fromCache", value: .bool(true)),
        ])
    }
}
