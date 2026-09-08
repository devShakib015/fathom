import Foundation

/// Turns whatever the model said into something Fathom can actually build.
///
/// A generated plan is treated as a suggestion, never as an instruction. Every
/// field is matched against the catalog, and anything unrecognisable falls back
/// to a sensible default — so the failure mode of a confused model is a widget
/// that is merely not what you asked for, rather than an error, a crash, or a
/// document full of names that mean nothing.
enum PlanMatcher {

    static func entry(for plan: Intelligence.WidgetPlan) -> CatalogEntry? {
        let template = match(plan.layout, in: Catalog.templates.map(\.id))
            ?? Catalog.templates.first?.id
        let theme = match(plan.palette, in: Theme.all.map(\.id)) ?? Theme.all[0].id
        let family = WidgetDoc.Family(rawValue: plan.size.trimmingCharacters(in: .whitespaces))

        guard let template else { return nil }

        // The chosen size only holds if the layout was composed for it.
        let candidates = Catalog.entries.filter { $0.templateID == template && $0.themeID == theme }
        return candidates.first { $0.family == family } ?? candidates.first
    }

    /// Exact, then case-insensitive, then closest by edit distance.
    ///
    /// Small models get ids nearly right far more often than they get them
    /// wrong — "clockstack" for "clock-stack", "mint-glass" for "mint". Taking
    /// the nearest match turns most near-misses into the intended answer.
    static func match(_ value: String, in options: [String]) -> String? {
        let needle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        if let exact = options.first(where: { $0.lowercased() == needle }) { return exact }

        let squashed = needle.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if let loose = options.first(where: {
            $0.lowercased().replacingOccurrences(of: "-", with: "") == squashed
        }) { return loose }

        let scored = options
            .map { ($0, distance(needle, $0.lowercased())) }
            .min { $0.1 < $1.1 }
        // Beyond a third of the length wrong, it is a different word, not a typo.
        guard let scored, scored.1 <= max(3, needle.count / 3) else { return nil }
        return scored.0
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1]
                    ? previous[j - 1]
                    : Swift.min(previous[j - 1], previous[j], current[j - 1]) + 1
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
