import SwiftUI

/// Draws a document.
///
/// This is the interpreter. The widget extension runs it on every timeline
/// reload and the editor runs it on every keystroke, and they must agree
/// exactly — an editor preview that differs from the placed widget is worse
/// than having no preview, because it teaches the user to distrust what they
/// see while designing.
struct WidgetCanvas: View {
    let doc: WidgetDoc
    let data: ResolvedData

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // One uniform scale for type, stroke widths and corner radii,
            // derived from the family this document was authored against.
            // Frames are already unit-space so they need no help; a 14 pt
            // label would otherwise stay 14 pt on a box that grew by 12 %.
            let reference = doc.family.referenceSize
            let scale = min(size.width / reference.width, size.height / reference.height)

            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(doc.elements) { element in
                    let rect = element.frame.resolved(in: size)
                    ElementView(element: element, data: data, scale: scale, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .opacity(element.style.opacity)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// One element, drawn.
struct ElementView: View {
    let element: Element
    let data: ResolvedData
    let scale: Double
    /// The element's own box, already resolved to points.
    let size: CGSize

    private var style: Style { element.style }

    var body: some View {
        switch element.kind {
        case .text:    text
        case .symbol:  symbol
        case .shape:   shape
        case .divider: divider
        case .arc:     arc
        case .spark:   spark
        }
    }

    // MARK: - Text

    private var text: some View {
        Text(data.text(for: element))
            .font(style.font.font(scale: scale))
            .foregroundStyle(style.foreground.color)
            .multilineTextAlignment(style.alignment.swiftUI)
            .lineLimit(style.lineLimit <= 0 ? nil : style.lineLimit)
            // Live values change length. A temperature that reads "7" today
            // and "-12" tomorrow must not clip, and shrinking is a better
            // failure than truncating a number.
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.frameAlignment)
    }

    // MARK: - Symbol

    private var symbol: some View {
        // The symbol name can itself be bound, so a widget can show
        // `cloud.rain` or `sun.max` from a weather endpoint's condition field.
        let name = data.text(for: element)
        return Image(systemName: name.isEmpty ? "questionmark" : name)
            .resizable()
            .scaledToFit()
            .fontWeight(style.font.weight.swiftUI)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(style.foreground.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.alignment.frameAlignment)
    }

    // MARK: - Shape

    private var shape: some View {
        RoundedRectangle(cornerRadius: style.cornerRadius * scale, style: .continuous)
            .fill((style.fill ?? style.foreground).color)
    }

    // MARK: - Divider

    private var divider: some View {
        // Orientation follows the box the user drew rather than a setting.
        // Dragging a divider tall to make it vertical is the gesture people
        // already expect from every drawing tool.
        let horizontal = size.width >= size.height
        let thickness = max(style.lineWidth * scale, 0.5)
        return RoundedRectangle(cornerRadius: thickness / 2, style: .continuous)
            .fill(style.foreground.color)
            .frame(width: horizontal ? nil : thickness,
                   height: horizontal ? thickness : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Arc

    private var arc: some View {
        let fraction = data.fraction(for: element)
        let width = max(style.lineWidth * scale, 1)
        return ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: width, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(fraction, 0.0001))
                .stroke(style.foreground.color,
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                // Trim starts at 3 o'clock; every progress ring anyone has
                // ever seen starts at 12.
                .rotationEffect(.degrees(-90))
        }
        .padding(width / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackColor: Color {
        style.fill?.color ?? style.foreground.color.opacity(0.18)
    }

    // MARK: - Sparkline

    private var spark: some View {
        let series = data.series(for: element)
        let width = max(style.lineWidth * scale * 0.5, 1)
        return Canvas { context, canvasSize in
            guard series.count >= 2 else { return }
            let low = series.min() ?? 0
            let high = series.max() ?? 1
            // A flat series has no range to normalise against; draw it down
            // the middle rather than dividing by zero or pinning it to the
            // floor, which would read as "zero" instead of "unchanging".
            let span = high - low
            let inset = width / 2
            let usableHeight = max(canvasSize.height - width, 1)

            func point(_ index: Int) -> CGPoint {
                let x = series.count == 1 ? 0 : Double(index) / Double(series.count - 1)
                let normalised = span == 0 ? 0.5 : (series[index] - low) / span
                return CGPoint(x: x * canvasSize.width,
                               y: inset + (1 - normalised) * usableHeight)
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<series.count { line.addLine(to: point(i)) }

            if let fill = style.fill {
                var area = line
                area.addLine(to: CGPoint(x: canvasSize.width, y: canvasSize.height))
                area.addLine(to: CGPoint(x: 0, y: canvasSize.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [fill.color, fill.color.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: canvasSize.height)))
            }

            context.stroke(line,
                           with: .color(style.foreground.color),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }
}
