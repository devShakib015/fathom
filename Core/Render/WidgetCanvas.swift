import SwiftUI

/// Draws a document.
///
/// This is the interpreter. The widget extension runs it on every timeline
/// reload and the editor runs it on every keystroke, and they must agree
/// exactly — an editor preview that differs from the placed widget is worse
/// than having no preview, because it teaches the user to distrust what they
/// see while designing.
/// Frames the editor is showing but has not written to the document.
///
/// Covers moving and resizing alike: both used to write into `model.doc` on
/// every mouse event, and both were capped at fifteen frames a second because
/// assigning `doc` rebuilds every view observing it.
struct LiveOffset: Equatable {
    var frames: [UUID: Frame]

    func frame(for element: Element) -> Frame { frames[element.id] ?? element.frame }
}

struct WidgetCanvas: View {
    let doc: WidgetDoc
    let data: ResolvedData
    /// What to do when an element with an action is clicked.
    ///
    /// Nil — the default, and what the widget extension always passes — makes
    /// every element inert. Interaction is therefore off by construction rather
    /// than by a flag somebody has to remember to clear: the extension cannot
    /// perform an action because it has nothing to perform it with. WidgetKit
    /// could not honour one anyway: App Intents were tried here and never ran
    /// a single timeline.
    var perform: ((Action) -> Void)?
    /// Elements being dragged, and how far, in unit space.
    ///
    /// Lets the editor show a drag without writing it into the document on
    /// every mouse event — the thing that was capping dragging at fifteen
    /// frames a second. Nil everywhere else, including the widget extension.
    var live: LiveOffset?

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
                ElementList(elements: doc.elements, doc: doc, data: data,
                            scope: .root, box: size, scale: scale, perform: perform,
                            live: live)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }
}

/// Lays a list of elements into a box. Recursive, so containers cost nothing
/// extra: a child's frame is unit-space inside its parent exactly as a
/// top-level element's is inside the widget.
struct ElementList: View {
    let elements: [Element]
    let doc: WidgetDoc
    let data: ResolvedData
    let scope: ResolvedData.Scope
    let box: CGSize
    let scale: Double
    var perform: ((Action) -> Void)?
    var live: LiveOffset?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(elements) { element in
                if data.isVisible(element, in: doc, scope: scope) {
                    let rect = (live?.frame(for: element) ?? element.frame).resolved(in: box)
                    PlacedElement(element: element, doc: doc, data: data, scope: scope,
                                  size: rect.size, scale: scale, perform: perform)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
    }
}

/// One element with its shared style chrome applied. Split from the drawing so
/// that opacity, rotation and shadow are written once rather than in each of
/// the ten kinds.
private struct PlacedElement: View {
    let element: Element
    let doc: WidgetDoc
    let data: ResolvedData
    let scope: ResolvedData.Scope
    let size: CGSize
    let scale: Double
    var perform: ((Action) -> Void)?

    private var action: Action? {
        guard let action = element.action, action.isSet, perform != nil else { return nil }
        return action
    }

    var body: some View {
        ElementView(element: element, doc: doc, data: data, scope: scope,
                    size: size, scale: scale, perform: perform)
            .opacity(element.style.opacity)
            .rotationEffect(.degrees(element.style.rotation))
            .shadow(color: element.style.shadowRadius > 0
                    ? element.style.shadowColor.color : .clear,
                    radius: element.style.shadowRadius * scale,
                    y: element.style.shadowY * scale)
            .modifier(Clickable(action: action, perform: perform))
    }
}

/// Makes an element clickable, and only when there is something to click for.
///
/// A separate modifier so the non-interactive path adds nothing at all — no
/// gesture, no hit-testing change, no pointer cursor. The extension renders the
/// same view it always did.
private struct Clickable: ViewModifier {
    let action: Action?
    let perform: ((Action) -> Void)?

    func body(content: Content) -> some View {
        if let action, let perform {
            content
                // The whole box, not just the drawn glyph: a click target the
                // size of a colon in a clock is not a click target.
                .contentShape(Rectangle())
                .onTapGesture { perform(action) }
                .pointerStyle(.link)
                .help(action.disclosure ?? "")
        } else {
            content
        }
    }
}

/// One element, drawn.
struct ElementView: View {
    let element: Element
    let doc: WidgetDoc
    let data: ResolvedData
    var scope: ResolvedData.Scope = .root
    /// The element's own box, already resolved to points.
    let size: CGSize
    let scale: Double
    /// Passed down so an action inside a group — or on one row of a repeater —
    /// works. A list of links is the case that makes repeaters worth clicking.
    var perform: ((Action) -> Void)?

    private var style: Style { element.style }

    var body: some View {
        switch element.kind {
        case .text:     text
        case .symbol:   symbol
        case .shape:    shape
        case .divider:  divider
        case .arc:      arc
        case .spark:    spark
        case .image:    image
        case .bar:      bar
        case .group:    group
        case .repeater: repeater
        }
    }

    // MARK: - Text

    private var text: some View {
        Text(data.text(for: element, scope: scope))
            .font(style.font.font(scale: scale))
            .tracking(style.tracking * scale)
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
        let name = data.text(for: element, scope: scope)
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
        let corner = RoundedRectangle(cornerRadius: style.cornerRadius * scale, style: .continuous)
        return corner
            .fill(.clear)
            .overlay(corner.fill(style.paint(style.fill ?? style.foreground)))
            .overlay(
                corner.strokeBorder(style.strokeColor?.color ?? .clear,
                                    lineWidth: style.strokeColor == nil ? 0 : style.strokeWidth * scale)
            )
            .clipShape(corner)
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
        let fraction = data.fraction(for: element, scope: scope)
        let width = max(style.lineWidth * scale, 1)
        // A sweep of less than a full turn is the open gauge every dashboard
        // uses; 360 keeps the plain ring.
        let sweep = min(max(style.arcSweep, 1), 360) / 360
        return ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(trackColor, style: StrokeStyle(lineWidth: width, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(fraction * sweep, 0.0001))
                .stroke(style.paint(style.foreground),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        // Trim starts at 3 o'clock; every progress ring anyone has ever seen
        // starts at 12, and `arcStart` turns it from there.
        .rotationEffect(.degrees(-90 + style.arcStart))
        .padding(width / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackColor: Color {
        style.fill?.color ?? style.foreground.color.opacity(0.18)
    }

    // MARK: - Bar

    private var bar: some View {
        let fraction = data.fraction(for: element, scope: scope)
        let vertical = size.height > size.width
        let radius = style.cornerRadius > 0
            ? style.cornerRadius * scale
            : min(size.width, size.height) / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack(alignment: vertical ? .bottom : .leading) {
            shape.fill(trackColor)
            shape.fill(style.paint(style.foreground))
                .frame(width: vertical ? nil : max(size.width * fraction, radius * 2),
                       height: vertical ? max(size.height * fraction, radius * 2) : nil)
        }
        .clipShape(shape)
    }

    // MARK: - Image

    @ViewBuilder
    private var image: some View {
        let url = data.text(for: element, scope: scope).trimmingCharacters(in: .whitespaces)
        let corner = RoundedRectangle(cornerRadius: style.cornerRadius * scale, style: .continuous)

        if let bytes = data.images[url], let loaded = NSImage(data: bytes) {
            // The two modes need the clip at different points, which is not a
            // detail that can be papered over: `fill` overflows the frame and
            // must be clipped to it, while `fit` letterboxes *inside* the frame,
            // so clipping the frame rounds empty space and leaves the picture
            // itself square. Set a corner radius in fit mode with one shared
            // order and nothing visibly happens.
            if style.contentMode == .fill {
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(corner)
            } else {
                Image(nsImage: loaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(corner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Not a blank box: an image that has not arrived should say so,
            // because "no picture" and "wrong URL" look identical otherwise.
            corner
                .fill(style.foreground.color.opacity(0.08))
                .overlay(
                    Image(systemName: url.isEmpty ? "photo" : "photo.badge.exclamationmark")
                        .font(.system(size: min(size.width, size.height) * 0.3, weight: .light))
                        .foregroundStyle(style.foreground.color.opacity(0.5))
                )
        }
    }

    // MARK: - Sparkline

    private var spark: some View {
        let series = data.series(for: element, scope: scope)
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

    // MARK: - Containers

    private var group: some View {
        ElementList(elements: element.children, doc: doc, data: data,
                    scope: scope, box: size, scale: scale, perform: perform)
    }

    /// One child template, drawn once per item of a bound array.
    ///
    /// Each row gets its own scope, so a child's key path resolves against the
    /// item rather than the source root and `index`/`total` mean something.
    /// That is what lets three elements describe seven days.
    private var repeater: some View {
        let rows = data.items(for: element, scope: scope)
        let limit = min(rows.count, Element.repeaterLimit)
        let vertical = size.height > size.width
        let spacing = style.lineWidth * scale

        return HVStack(vertical: vertical, spacing: spacing) {
            ForEach(0..<limit, id: \.self) { index in
                GeometryReader { cell in
                    ElementList(elements: element.children, doc: doc, data: data,
                                scope: ResolvedData.Scope(item: rows[index],
                                                          index: index,
                                                          total: limit),
                                box: cell.size, scale: scale, perform: perform)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A stack whose axis is decided at runtime, since a repeater's direction comes
/// from the shape the user drew rather than from a setting.
private struct HVStack<Content: View>: View {
    let vertical: Bool
    let spacing: Double
    @ViewBuilder var content: Content

    var body: some View {
        if vertical {
            VStack(spacing: spacing) { content }
        } else {
            HStack(spacing: spacing) { content }
        }
    }
}
