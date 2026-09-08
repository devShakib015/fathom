import Foundation

/// Compact builders for laying out a template.
///
/// Templates are written against these rather than against `Element` directly,
/// so a layout reads as a description of itself and stays around twenty-five
/// lines. That matters more than it sounds: the size of the catalog is
/// templates × themes, so the cost of writing one template is the thing that
/// decides whether the catalog has hundreds of entries or thousands.
enum Kit {
    static func text(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     size: Double,
                     weight: FontSpec.Weight = .regular,
                     design: FontSpec.Design = .default,
                     colour: ColorSpec,
                     align: TextAlignment = .leading,
                     lines: Int = 1,
                     tracking: Double = 0,
                     literal: String = "",
                     bind: DataBinding? = nil) -> Element {
        Element(name: name, kind: .text,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(font: FontSpec(size: size, weight: weight, design: design),
                             foreground: colour, alignment: align, lineLimit: lines,
                             tracking: tracking),
                text: literal, binding: bind)
    }

    static func symbol(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                       colour: ColorSpec,
                       align: TextAlignment = .center,
                       literal: String = "star.fill",
                       bind: DataBinding? = nil) -> Element {
        Element(name: name, kind: .symbol,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(foreground: colour, alignment: align),
                text: literal, binding: bind)
    }

    static func arc(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                    colour: ColorSpec, track: ColorSpec, width: Double = 7,
                    sweep: Double = 360, start: Double = 0,
                    gradient: ColorSpec? = nil,
                    literal: String = "0.5",
                    bind: DataBinding? = nil) -> Element {
        Element(name: name, kind: .arc,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(foreground: colour, fill: track, lineWidth: width,
                             gradientEnd: gradient, arcStart: start, arcSweep: sweep),
                text: literal, binding: bind)
    }

    static func bar(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                    colour: ColorSpec, track: ColorSpec,
                    corner: Double = 0, gradient: ColorSpec? = nil,
                    literal: String = "0.5",
                    bind: DataBinding? = nil) -> Element {
        Element(name: name, kind: .bar,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(foreground: colour, fill: track, cornerRadius: corner,
                             gradientEnd: gradient),
                text: literal, binding: bind)
    }

    static func rule(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     colour: ColorSpec, width: Double = 1) -> Element {
        Element(name: "Rule", kind: .divider,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(foreground: colour, lineWidth: width))
    }

    static func shape(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                      fill: ColorSpec, corner: Double = 12,
                      gradient: ColorSpec? = nil, stroke: ColorSpec? = nil) -> Element {
        Element(name: name, kind: .shape,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(fill: fill, cornerRadius: corner,
                             strokeColor: stroke, gradientEnd: gradient))
    }

    static func spark(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                      colour: ColorSpec, fill: ColorSpec?, width: Double = 5,
                      literal: String = "12,15,13,19,17,24,22,29",
                      bind: DataBinding? = nil) -> Element {
        Element(name: name, kind: .spark,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(foreground: colour, fill: fill, lineWidth: width),
                text: literal, binding: bind)
    }

    static func repeater(_ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                         spacing: Double = 3,
                         bind: DataBinding,
                         children: [Element]) -> Element {
        Element(name: name, kind: .repeater,
                frame: Frame(x: x, y: y, width: w, height: h),
                style: Style(lineWidth: spacing),
                binding: bind, children: children)
    }

    // MARK: - Bindings

    static func bind(_ source: UUID, _ path: String, _ format: Format,
                     fallback: String = "—", expression: String? = nil) -> DataBinding {
        DataBinding(sourceID: source, keyPath: path, expression: expression,
                    format: format, fallback: fallback)
    }

    static func time(_ source: UUID, _ style: Format.DateStyle = .time, prefix: String = "") -> DataBinding {
        bind(source, "date.now", Format(kind: .date, dateStyle: style, prefix: prefix), fallback: "--:--")
    }

    static func percent(_ source: UUID, _ path: String) -> DataBinding {
        bind(source, path, Format(kind: .percent), fallback: "—")
    }

    static func bytes(_ source: UUID, _ path: String) -> DataBinding {
        bind(source, path, Format(kind: .bytes), fallback: "—")
    }
}
