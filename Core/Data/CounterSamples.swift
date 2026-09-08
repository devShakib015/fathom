import Foundation

/// Remembers a counter between reloads so a rate can be computed from it.
///
/// CPU time and network bytes are cumulative counters: a single reading says
/// nothing, and the interesting number is the difference between two. A widget
/// extension is a fresh process on nearly every reload and cannot hold that
/// state in memory, so it goes in the shared store.
///
/// This is one of the few places the 64-second floor is an advantage rather
/// than a constraint. The interval is regular, known and short enough that a
/// difference over it is a meaningful rate — on iOS, where a widget might not
/// run for hours, the same arithmetic would produce a number that averaged
/// away everything worth seeing.
struct CounterSamples {
    struct Sample: Codable {
        var at: Date
        var values: [String: Double]
    }

    private static var url: URL? {
        SharedStore.container?.appendingPathComponent("samples.json")
    }

    static func previous() -> Sample? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Sample.self, from: data)
    }

    static func record(_ values: [String: Double], at date: Date) {
        guard let url, let data = try? JSONEncoder().encode(Sample(at: date, values: values)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Change per second since the last reading, or nil when there is nothing
    /// to compare against or the counter went backwards (a reboot, or an
    /// interface being reset).
    static func rate(_ key: String, now: Double, at date: Date, previous: Sample?) -> Double? {
        guard let previous, let before = previous.values[key] else { return nil }
        let elapsed = date.timeIntervalSince(previous.at)
        guard elapsed > 0.5, now >= before else { return nil }
        return (now - before) / elapsed
    }
}
