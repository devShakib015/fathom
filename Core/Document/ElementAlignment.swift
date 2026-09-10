import Foundation

/// Lining elements up with one another, or with the widget.
///
/// Named `ElementAlignment`, not `Alignment`: SwiftUI has its own `Alignment`
/// and a bare one here shadows it wherever Core and SwiftUI meet. The same
/// collision already cost this project once, which is why the binding type is
/// called `DataBinding`.
///
/// In `Core` rather than beside the editor because it is arithmetic over
/// frames, not behaviour of a view — and because logic that cannot be tested
/// without a window tends not to be tested at all.
enum ElementAlignment: String, CaseIterable, Identifiable, Sendable {
    case left, centreX, right, top, centreY, bottom
    case spreadX, spreadY

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .left: "align.horizontal.left.fill"
        case .centreX: "align.horizontal.center.fill"
        case .right: "align.horizontal.right.fill"
        case .top: "align.vertical.top.fill"
        case .centreY: "align.vertical.center.fill"
        case .bottom: "align.vertical.bottom.fill"
        case .spreadX: "distribute.horizontal.fill"
        case .spreadY: "distribute.vertical.fill"
        }
    }

    /// Plain words. "Distribute horizontally" is a term of art; "space evenly
    /// across" is what it does.
    var label: String {
        switch self {
        case .left: "Align left"
        case .centreX: "Centre across"
        case .right: "Align right"
        case .top: "Align top"
        case .centreY: "Centre down"
        case .bottom: "Align bottom"
        case .spreadX: "Space evenly across"
        case .spreadY: "Space evenly down"
        }
    }

    /// Spreading three things needs three things.
    var needsThree: Bool { self == .spreadX || self == .spreadY }

    /// Where each element should end up, or nil when the request cannot be
    /// honoured.
    ///
    /// With one element the widget itself is what to line up against —
    /// "centre this" is the single most common thing anyone wants from an
    /// editor and there was no way to ask for it. With several they line up
    /// against each other's bounding box, which is what every comparable tool
    /// does.
    static func positions(for alignment: ElementAlignment,
                          in elements: [Element]) -> [UUID: Frame]? {
        guard !elements.isEmpty else { return nil }
        guard !(alignment.needsThree && elements.count < 3) else { return nil }

        let box: (minX: Double, maxX: Double, minY: Double, maxY: Double)
        if elements.count == 1 {
            box = (0, 1, 0, 1)
        } else {
            box = (elements.map(\.frame.x).min() ?? 0,
                   elements.map { $0.frame.x + $0.frame.width }.max() ?? 1,
                   elements.map(\.frame.y).min() ?? 0,
                   elements.map { $0.frame.y + $0.frame.height }.max() ?? 1)
        }

        var result: [UUID: Frame] = [:]

        if alignment.needsThree {
            // Computed up front: where each one goes depends on its rank among
            // the others, which a per-element pass cannot see.
            let horizontal = alignment == .spreadX
            let sorted = elements.sorted {
                (horizontal ? $0.frame.x : $0.frame.y) < (horizontal ? $1.frame.x : $1.frame.y)
            }
            let extent = horizontal ? box.maxX - box.minX : box.maxY - box.minY
            let used = sorted.reduce(0.0) { $0 + (horizontal ? $1.frame.width : $1.frame.height) }
            let gap = (extent - used) / Double(sorted.count - 1)
            var cursor = horizontal ? box.minX : box.minY
            for element in sorted {
                var frame = element.frame
                if horizontal { frame.x = cursor } else { frame.y = cursor }
                result[element.id] = frame
                cursor += (horizontal ? element.frame.width : element.frame.height) + gap
            }
            return result
        }

        for element in elements {
            var frame = element.frame
            switch alignment {
            case .left: frame.x = box.minX
            case .right: frame.x = box.maxX - frame.width
            case .centreX: frame.x = (box.minX + box.maxX) / 2 - frame.width / 2
            case .top: frame.y = box.minY
            case .bottom: frame.y = box.maxY - frame.height
            case .centreY: frame.y = (box.minY + box.maxY) / 2 - frame.height / 2
            case .spreadX, .spreadY: break
            }
            result[element.id] = frame
        }
        return result
    }
}
