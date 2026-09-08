import SwiftUI

/// The document background, as a SwiftUI style.
///
/// Split from the canvas because a widget must apply it through
/// `containerBackground` — WidgetKit reads that modifier to decide how the
/// widget sits on the desktop — while the editor has to draw the same thing
/// as an ordinary shape behind the canvas.
extension Background {

    @ViewBuilder
    var swatch: some View {
        switch kind {
        case .none:
            Color.clear
        case .color:
            color.color
        case .gradient:
            LinearGradient(colors: [color.color, gradientEnd.color],
                           startPoint: gradientStart,
                           endPoint: gradientEndPoint)
        case .glass:
            // Tahoe's material. This is what macOS 26 buys and it is why the
            // deployment target is 26.0: the same widget on an older release
            // gets an opaque plate instead of the desktop showing through.
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var gradientStart: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private var gradientEndPoint: UnitPoint {
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }
}

extension View {
    /// Applies a document's background inside a widget.
    @ViewBuilder
    func fathomWidgetBackground(_ background: Background) -> some View {
        switch background.kind {
        case .none:
            containerBackground(.clear, for: .widget)
        case .color:
            containerBackground(background.color.color, for: .widget)
        case .gradient:
            containerBackground(for: .widget) { background.swatch }
        case .glass:
            containerBackground(.fill.tertiary, for: .widget)
        }
    }
}
