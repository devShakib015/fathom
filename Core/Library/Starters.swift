import Foundation

/// Documents Fathom ships with.
///
/// These are ordinary documents, built from the same six primitives and the
/// same bindings a user gets. That is deliberate: the library is the on-ramp,
/// and a starter that used private capabilities would teach the wrong thing
/// the moment somebody opened it to see how it was made.
enum Starters {

    static var all: [WidgetDoc] { [systemSmall, refreshFloorMedium, weatherMedium, vitalsMedium, weekAheadLarge, menuBarClock, islandNow] }

    /// Stable ids so that reinstalling Fathom updates the starters in place
    /// rather than duplicating them beside the user's edited copies.
    private static let systemSourceID = UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000001")!

    private static func systemSource() -> DataSource {
        DataSource(id: systemSourceID, name: "System", kind: .system)
    }

    // MARK: - System, small

    static var systemSmall: WidgetDoc {
        let source = systemSource()
        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A1")!,
            name: "System",
            family: .small,
            background: .glass,
            elements: [
                Element(
                    name: "Time",
                    kind: .text,
                    frame: Frame(x: 0.075, y: 0.075, width: 0.85, height: 0.27),
                    style: Style(font: FontSpec(size: 42, weight: .semibold, design: .rounded),
                                 foreground: .text,
                                 alignment: .leading),
                    text: "18:42",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "date.now",
                                     format: Format(kind: .date, dateStyle: .time),
                                     fallback: "--:--")),

                Element(
                    name: "Weekday",
                    kind: .text,
                    frame: Frame(x: 0.08, y: 0.365, width: 0.46, height: 0.10),
                    style: Style(font: FontSpec(size: 11, weight: .medium),
                                 foreground: .dim,
                                 alignment: .leading),
                    text: "Monday",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "date.now",
                                     format: Format(kind: .date, dateStyle: .weekday),
                                     fallback: "—")),

                Element(
                    name: "Date",
                    kind: .text,
                    frame: Frame(x: 0.46, y: 0.365, width: 0.46, height: 0.10),
                    style: Style(font: FontSpec(size: 11, weight: .medium),
                                 foreground: .dim,
                                 alignment: .trailing),
                    text: "8 Sep",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "date.now",
                                     format: Format(kind: .date, dateStyle: .monthDay),
                                     fallback: "—")),

                Element(
                    name: "Rule",
                    kind: .divider,
                    frame: Frame(x: 0.08, y: 0.50, width: 0.84, height: 0.02),
                    style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.28),
                                 lineWidth: 1)),

                Element(
                    name: "Battery ring",
                    kind: .arc,
                    frame: Frame(x: 0.075, y: 0.575, width: 0.31, height: 0.31),
                    style: Style(foreground: .accent,
                                 fill: ColorSpec(Palette.accentHex, opacity: 0.16),
                                 lineWidth: 6),
                    text: "0.9",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "battery.percent",
                                     format: Format(kind: .percent),
                                     fallback: "0")),

                Element(
                    name: "Battery label",
                    kind: .text,
                    frame: Frame(x: 0.075, y: 0.575, width: 0.31, height: 0.31),
                    style: Style(font: FontSpec(size: 11, weight: .semibold),
                                 foreground: .text,
                                 alignment: .center),
                    text: "90%",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "battery.percent",
                                     format: Format(kind: .percent),
                                     fallback: "—")),

                Element(
                    name: "Disk free",
                    kind: .text,
                    frame: Frame(x: 0.42, y: 0.585, width: 0.50, height: 0.17),
                    style: Style(font: FontSpec(size: 20, weight: .semibold, design: .rounded),
                                 foreground: .text,
                                 alignment: .trailing),
                    text: "217 GB",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "disk.free",
                                     format: Format(kind: .bytes),
                                     fallback: "—")),

                Element(
                    name: "Disk caption",
                    kind: .text,
                    frame: Frame(x: 0.42, y: 0.755, width: 0.50, height: 0.11),
                    style: Style(font: FontSpec(size: 10, weight: .medium),
                                 foreground: .dim,
                                 alignment: .trailing),
                    text: "free"),
            ],
            sources: [source])
    }

    // MARK: - Refresh floor, medium

    /// The instrument, not a decoration. It shows seconds — which every other
    /// Fathom design should avoid, because a 64-second floor cannot honestly
    /// imply sub-minute precision — precisely so the cadence is watchable on a
    /// real desktop rather than only in a log.
    static var refreshFloorMedium: WidgetDoc {
        let source = systemSource()
        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A2")!,
            name: "Refresh floor",
            family: .medium,
            background: .glass,
            elements: [
                Element(
                    name: "Caption",
                    kind: .text,
                    frame: Frame(x: 0.045, y: 0.13, width: 0.55, height: 0.11),
                    style: Style(font: FontSpec(size: 10, weight: .semibold),
                                 foreground: .dim,
                                 alignment: .leading),
                    text: "LAST TIMELINE RELOAD"),

                Element(
                    name: "Stamp",
                    kind: .text,
                    frame: Frame(x: 0.04, y: 0.26, width: 0.58, height: 0.38),
                    style: Style(font: FontSpec(size: 46, weight: .semibold, design: .rounded),
                                 foreground: .text,
                                 alignment: .leading),
                    text: "18:42:07",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "date.now",
                                     format: Format(kind: .date, dateStyle: .timeWithSeconds),
                                     fallback: "--:--:--")),

                Element(
                    name: "Date",
                    kind: .text,
                    frame: Frame(x: 0.045, y: 0.665, width: 0.55, height: 0.12),
                    style: Style(font: FontSpec(size: 12, weight: .medium),
                                 foreground: .dim,
                                 alignment: .leading),
                    text: "Monday 8 September 2026",
                    binding: DataBinding(sourceID: source.id,
                                     keyPath: "date.now",
                                     format: Format(kind: .date, dateStyle: .fullDate),
                                     fallback: "—")),

                Element(
                    name: "Rule",
                    kind: .divider,
                    frame: Frame(x: 0.655, y: 0.16, width: 0.012, height: 0.68),
                    style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.25),
                                 lineWidth: 1)),

                Element(
                    name: "Floor",
                    kind: .text,
                    frame: Frame(x: 0.70, y: 0.28, width: 0.26, height: 0.26),
                    style: Style(font: FontSpec(size: 38, weight: .semibold, design: .rounded),
                                 foreground: .accent,
                                 alignment: .leading),
                    text: "64s"),

                Element(
                    name: "Floor caption",
                    kind: .text,
                    frame: Frame(x: 0.705, y: 0.56, width: 0.26, height: 0.22),
                    style: Style(font: FontSpec(size: 10, weight: .medium),
                                 foreground: .dim,
                                 alignment: .leading,
                                 lineLimit: 2),
                    text: "measured\nmacOS floor"),
            ],
            sources: [source])
    }

    // MARK: - Smoke test

    /// Every primitive at once, in one document.
    ///
    /// Not shipped in the library — its sparkline is a literal series rather
    /// than real data, and a starter should never teach that. It exists so
    /// that "all six primitives still render" is a thing that can be checked
    /// with a picture after any change to the interpreter, rather than
    /// believed. The app renders it into `Previews/` on every launch.
    static var smokeTest: WidgetDoc {
        let source = systemSource()
        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000FF")!,
            name: "Vocabulary",
            family: .large,
            background: .glass,
            elements: [
                Element(name: "Card", kind: .shape,
                        frame: Frame(x: 0.05, y: 0.05, width: 0.90, height: 0.26),
                        style: Style(fill: ColorSpec(Palette.accentHex, opacity: 0.10),
                                     cornerRadius: 14)),
                Element(name: "Icon", kind: .symbol,
                        frame: Frame(x: 0.09, y: 0.10, width: 0.14, height: 0.14),
                        style: Style(font: FontSpec(size: 20, weight: .semibold),
                                     foreground: .accent, alignment: .center),
                        text: "internaldrive"),
                Element(name: "Icon bound", kind: .symbol,
                        frame: Frame(x: 0.78, y: 0.10, width: 0.13, height: 0.13),
                        style: Style(font: FontSpec(size: 18, weight: .regular),
                                     foreground: ColorSpec(Palette.accentAltHex), alignment: .center),
                        text: "bolt.fill"),
                Element(name: "Heading", kind: .text,
                        frame: Frame(x: 0.26, y: 0.115, width: 0.50, height: 0.09),
                        style: Style(font: FontSpec(size: 17, weight: .semibold),
                                     foreground: .text),
                        text: "226 GB",
                        binding: DataBinding(sourceID: source.id, keyPath: "disk.free",
                                         format: Format(kind: .bytes), fallback: "—")),
                Element(name: "Sub", kind: .text,
                        frame: Frame(x: 0.265, y: 0.205, width: 0.50, height: 0.07),
                        style: Style(font: FontSpec(size: 11), foreground: .dim),
                        text: "free on this Mac"),
                Element(name: "Rule", kind: .divider,
                        frame: Frame(x: 0.08, y: 0.355, width: 0.84, height: 0.012),
                        style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.3), lineWidth: 1)),
                Element(name: "Ring", kind: .arc,
                        frame: Frame(x: 0.08, y: 0.41, width: 0.30, height: 0.30),
                        style: Style(foreground: .accent,
                                     fill: ColorSpec(Palette.accentHex, opacity: 0.15), lineWidth: 8),
                        text: "0.45",
                        binding: DataBinding(sourceID: source.id, keyPath: "disk.usedFraction",
                                         format: Format(kind: .percent), fallback: "0")),
                Element(name: "Spark", kind: .spark,
                        frame: Frame(x: 0.44, y: 0.42, width: 0.48, height: 0.26),
                        style: Style(foreground: ColorSpec(Palette.accentAltHex),
                                     fill: ColorSpec(Palette.accentAltHex, opacity: 0.35), lineWidth: 6),
                        text: "12,15,13,19,17,24,22,29,26,33"),
                Element(name: "Vertical rule", kind: .divider,
                        frame: Frame(x: 0.40, y: 0.42, width: 0.012, height: 0.26),
                        style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.3), lineWidth: 1)),
                Element(name: "Footer", kind: .text,
                        frame: Frame(x: 0.08, y: 0.78, width: 0.84, height: 0.12),
                        style: Style(font: FontSpec(size: 11), foreground: .dim,
                                     alignment: .center, lineLimit: 2),
                        text: "shape · symbol · text · divider · arc · spark"),
            ],
            sources: [source])
    }

    // MARK: - Weather, medium

    /// The one that makes the reload finding visible.
    ///
    /// A live endpoint, refreshed on the 64-second floor, showing numbers that
    /// are never more than a minute old. Every iOS widget builder shows this
    /// same data hours stale, and not because they built it badly.
    ///
    /// The coordinates are Dubai because they have to be something; the URL is
    /// an ordinary editable field, and changing `latitude`/`longitude` is the
    /// first thing anyone will do. Open-Meteo needs no key and no account,
    /// which is why it is the one endpoint worth shipping pointed at.
    static var weatherMedium: WidgetDoc {
        let system = systemSource()
        let weather = DataSource(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000002")!,
            name: "Open-Meteo",
            kind: .json,
            url: "https://api.open-meteo.com/v1/forecast?latitude=25.2048&longitude=55.2708"
               + "&current=temperature_2m,relative_humidity_2m,weather_code,is_day"
               + "&daily=temperature_2m_max&forecast_days=7&timezone=auto")

        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A3")!,
            name: "Weather",
            family: .medium,
            background: .glass,
            elements: [
                // The icon follows the actual sky, which needs a lookup table
                // rather than a binding — a WMO code is a number and an SF
                // Symbol is a name, and nothing but a transform gets from one
                // to the other. Nested so night is not drawn as daylight.
                Element(name: "Icon", kind: .symbol,
                        frame: Frame(x: 0.045, y: 0.19, width: 0.095, height: 0.25),
                        style: Style(font: FontSpec(size: 18, weight: .regular),
                                     foreground: .accent, alignment: .center),
                        text: "sun.max.fill",
                        binding: DataBinding(
                            sourceID: weather.id,
                            keyPath: "current.weather_code",
                            expression: """
                            if(current.is_day == 0,
                               map(value, 0, "moon.stars.fill", 1, "moon.stars.fill", \
                                          2, "cloud.moon.fill", 3, "cloud.fill", \
                                          45, "cloud.fog.fill", 48, "cloud.fog.fill", \
                                          51, "cloud.drizzle.fill", 61, "cloud.rain.fill", \
                                          63, "cloud.rain.fill", 65, "cloud.heavyrain.fill", \
                                          71, "cloud.snow.fill", 80, "cloud.heavyrain.fill", \
                                          95, "cloud.bolt.rain.fill", "cloud.fill"),
                               map(value, 0, "sun.max.fill", 1, "sun.max.fill", \
                                          2, "cloud.sun.fill", 3, "cloud.fill", \
                                          45, "cloud.fog.fill", 48, "cloud.fog.fill", \
                                          51, "cloud.drizzle.fill", 61, "cloud.rain.fill", \
                                          63, "cloud.rain.fill", 65, "cloud.heavyrain.fill", \
                                          71, "cloud.snow.fill", 80, "cloud.heavyrain.fill", \
                                          95, "cloud.bolt.rain.fill", "cloud.fill"))
                            """,
                            format: Format(kind: .text),
                            fallback: "questionmark")),

                Element(name: "Temperature", kind: .text,
                        frame: Frame(x: 0.165, y: 0.11, width: 0.33, height: 0.35),
                        style: Style(font: FontSpec(size: 40, weight: .semibold, design: .rounded),
                                     foreground: .text),
                        text: "36.7°",
                        binding: DataBinding(sourceID: weather.id,
                                             keyPath: "current.temperature_2m",
                                             format: Format(kind: .number, precision: 1, suffix: "°"),
                                             fallback: "—")),

                Element(name: "Place", kind: .text,
                        frame: Frame(x: 0.17, y: 0.50, width: 0.33, height: 0.14),
                        style: Style(font: FontSpec(size: 12, weight: .medium), foreground: .dim),
                        text: "Dubai"),

                Element(name: "Observed", kind: .text,
                        frame: Frame(x: 0.17, y: 0.655, width: 0.33, height: 0.13),
                        style: Style(font: FontSpec(size: 10), foreground: .dim),
                        text: "at 17:30",
                        binding: DataBinding(sourceID: weather.id,
                                             keyPath: "current.time",
                                             format: Format(kind: .date, dateStyle: .time, prefix: "at "),
                                             fallback: "offline")),

                Element(name: "Rule", kind: .divider,
                        frame: Frame(x: 0.515, y: 0.18, width: 0.012, height: 0.64),
                        style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.25),
                                     lineWidth: 1)),

                Element(name: "Week ahead", kind: .spark,
                        frame: Frame(x: 0.565, y: 0.17, width: 0.39, height: 0.30),
                        style: Style(foreground: ColorSpec(Palette.accentAltHex),
                                     fill: ColorSpec(Palette.accentAltHex, opacity: 0.28),
                                     lineWidth: 5),
                        text: "0",
                        binding: DataBinding(sourceID: weather.id,
                                             keyPath: "daily.temperature_2m_max",
                                             format: Format(kind: .text),
                                             fallback: "0")),

                // Sits tight under the sparkline it names, with a clear gap
                // before the humidity below. Evenly spaced, it read as a label
                // for the wrong number.
                Element(name: "Spark caption", kind: .text,
                        frame: Frame(x: 0.57, y: 0.49, width: 0.39, height: 0.11),
                        style: Style(font: FontSpec(size: 9, weight: .semibold), foreground: .dim),
                        text: "SEVEN-DAY HIGH"),

                Element(name: "Humidity", kind: .text,
                        frame: Frame(x: 0.57, y: 0.675, width: 0.39, height: 0.15),
                        style: Style(font: FontSpec(size: 12, weight: .medium), foreground: .text),
                        text: "humidity 53%",
                        binding: DataBinding(sourceID: weather.id,
                                             keyPath: "current.relative_humidity_2m",
                                             format: Format(kind: .percent, prefix: "humidity "),
                                             fallback: "humidity —")),
            ],
            sources: [system, weather])
    }

    // MARK: - Mac vitals, medium

    /// What the machine is doing, on a 64-second tick.
    ///
    /// CPU and network are rates rather than levels: the kernel reports
    /// cumulative counters, so the number comes from the difference between
    /// this reload and the last. That arithmetic only means anything because
    /// the interval is regular and short — the same widget on iOS would be
    /// averaging over however many hours the system felt like waiting.
    static var vitalsMedium: WidgetDoc {
        let source = systemSource()

        func row(_ name: String, y: Double, label: String, barPath: String,
                 valuePath: String, valueFormat: Format, tint: String) -> [Element] {
            [
                Element(name: "\(name) label", kind: .text,
                        frame: Frame(x: 0.05, y: y - 0.055, width: 0.17, height: 0.11),
                        style: Style(font: FontSpec(size: 11, weight: .medium), foreground: .dim),
                        text: label),
                Element(name: "\(name) bar", kind: .bar,
                        frame: Frame(x: 0.24, y: y - 0.022, width: 0.48, height: 0.045),
                        style: Style(foreground: ColorSpec(tint),
                                     fill: ColorSpec(tint, opacity: 0.15)),
                        text: "0",
                        binding: DataBinding(sourceID: source.id, keyPath: barPath,
                                             format: Format(kind: .percent), fallback: "0")),
                Element(name: "\(name) value", kind: .text,
                        frame: Frame(x: 0.74, y: y - 0.062, width: 0.21, height: 0.12),
                        style: Style(font: FontSpec(size: 11, weight: .semibold),
                                     foreground: .text, alignment: .trailing),
                        text: "—",
                        binding: DataBinding(sourceID: source.id, keyPath: valuePath,
                                             format: valueFormat, fallback: "—")),
            ]
        }

        var elements: [Element] = [
            Element(name: "Title", kind: .text,
                    frame: Frame(x: 0.05, y: 0.06, width: 0.45, height: 0.11),
                    style: Style(font: FontSpec(size: 9, weight: .semibold), foreground: .dim),
                    text: "THIS MAC"),
            Element(name: "Uptime", kind: .text,
                    frame: Frame(x: 0.52, y: 0.06, width: 0.43, height: 0.11),
                    style: Style(font: FontSpec(size: 9), foreground: .dim, alignment: .trailing),
                    text: "up —",
                    binding: DataBinding(sourceID: source.id, keyPath: "system.uptime",
                                         format: Format(kind: .duration, prefix: "up "),
                                         fallback: "up —")),
        ]
        elements += row("CPU", y: 0.34, label: "CPU", barPath: "cpu.usage",
                        valuePath: "cpu.usage", valueFormat: Format(kind: .percent),
                        tint: Palette.accentHex)
        elements += row("Memory", y: 0.58, label: "Memory", barPath: "memory.usedFraction",
                        valuePath: "memory.usedFraction", valueFormat: Format(kind: .percent),
                        tint: Palette.accentAltHex)
        elements += row("Disk", y: 0.82, label: "Disk", barPath: "disk.usedFraction",
                        valuePath: "disk.free", valueFormat: Format(kind: .bytes),
                        tint: Palette.accentHex)

        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A4")!,
            name: "Mac vitals",
            family: .medium,
            background: .glass,
            elements: elements,
            sources: [source])
    }

    // MARK: - Week ahead, large

    /// Seven days drawn by three elements.
    ///
    /// The repeater walks `daily.time`; each column reaches the matching
    /// temperature with `at(field(...), index)`, and the bar's height is that
    /// temperature normalised against the week's own range. Without expressions
    /// this widget needs twenty-one elements and a person to keep them in step.
    static var weekAheadLarge: WidgetDoc {
        let system = systemSource()
        let weather = DataSource(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000003")!,
            name: "Open-Meteo",
            kind: .json,
            url: "https://api.open-meteo.com/v1/forecast?latitude=25.2048&longitude=55.2708"
               + "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max"
               + "&forecast_days=7&timezone=auto")

        let highs = "field(\"daily.temperature_2m_max\")"

        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A5")!,
            name: "Week ahead",
            family: .large,
            background: .glass,
            elements: [
                Element(name: "Caption", kind: .text,
                        frame: Frame(x: 0.06, y: 0.055, width: 0.5, height: 0.05),
                        style: Style(font: FontSpec(size: 9, weight: .semibold), foreground: .dim),
                        text: "WEEK AHEAD"),

                Element(name: "Now", kind: .text,
                        frame: Frame(x: 0.055, y: 0.10, width: 0.5, height: 0.13),
                        style: Style(font: FontSpec(size: 34, weight: .semibold, design: .rounded),
                                     foreground: .text),
                        text: "36°",
                        binding: DataBinding(sourceID: weather.id,
                                             keyPath: "current.temperature_2m",
                                             format: Format(kind: .number, suffix: "°"),
                                             fallback: "—")),

                Element(name: "Sky", kind: .symbol,
                        frame: Frame(x: 0.79, y: 0.095, width: 0.13, height: 0.10),
                        style: Style(foreground: .accent, alignment: .center),
                        text: "sun.max.fill",
                        binding: DataBinding(
                            sourceID: weather.id,
                            keyPath: "current.weather_code",
                            expression: "map(value, 0, \"sun.max.fill\", 1, \"sun.max.fill\", "
                                      + "2, \"cloud.sun.fill\", 3, \"cloud.fill\", "
                                      + "45, \"cloud.fog.fill\", 61, \"cloud.rain.fill\", "
                                      + "95, \"cloud.bolt.rain.fill\", \"cloud.fill\")",
                            format: Format(kind: .text),
                            fallback: "questionmark")),

                Element(name: "Rule", kind: .divider,
                        frame: Frame(x: 0.06, y: 0.26, width: 0.88, height: 0.01),
                        style: Style(foreground: ColorSpec(Palette.textDimHex, opacity: 0.22),
                                     lineWidth: 1)),

                Element(name: "Seven days", kind: .repeater,
                        frame: Frame(x: 0.05, y: 0.32, width: 0.90, height: 0.56),
                        style: Style(lineWidth: 3),
                        binding: DataBinding(sourceID: weather.id, keyPath: "daily.time",
                                             format: Format(kind: .text), fallback: ""),
                        children: [
                            Element(name: "High", kind: .text,
                                    frame: Frame(x: 0, y: 0, width: 1, height: 0.13),
                                    style: Style(font: FontSpec(size: 10, weight: .semibold),
                                                 foreground: .text, alignment: .center),
                                    text: "—",
                                    binding: DataBinding(
                                        sourceID: weather.id, keyPath: "",
                                        expression: "at(\(highs), index)",
                                        format: Format(kind: .number, suffix: "°"),
                                        fallback: "—")),

                            Element(name: "Column", kind: .bar,
                                    frame: Frame(x: 0.26, y: 0.16, width: 0.48, height: 0.68),
                                    style: Style(foreground: ColorSpec(Palette.accentHex),
                                                 fill: ColorSpec(Palette.accentHex, opacity: 0.12),
                                                 cornerRadius: 4,
                                                 gradientEnd: ColorSpec(Palette.accentAltHex)),
                                    text: "0",
                                    binding: DataBinding(
                                        sourceID: weather.id, keyPath: "",
                                        // Normalised against the week's own
                                        // range, then floored so the coolest
                                        // day is a short bar rather than none.
                                        expression: "coalesce((at(\(highs), index) - lowest(\(highs))) "
                                                  + "/ (highest(\(highs)) - lowest(\(highs))), 0.5) "
                                                  + "* 0.82 + 0.18",
                                        format: Format(kind: .percent),
                                        fallback: "0")),

                            Element(name: "Day", kind: .text,
                                    frame: Frame(x: 0, y: 0.87, width: 1, height: 0.13),
                                    style: Style(font: FontSpec(size: 9, weight: .medium),
                                                 foreground: .dim, alignment: .center),
                                    text: "—",
                                    binding: DataBinding(
                                        sourceID: weather.id, keyPath: "",
                                        format: Format(kind: .date, dateStyle: .shortWeekday),
                                        fallback: "—")),
                        ]),

                Element(name: "Footer", kind: .text,
                        frame: Frame(x: 0.06, y: 0.925, width: 0.88, height: 0.05),
                        style: Style(font: FontSpec(size: 8), foreground: .dim, alignment: .center),
                        text: "Dubai · Open-Meteo · refreshed every 64 s"),
            ],
            sources: [system, weather])
    }

    // MARK: - Menu bar clock

    /// Ships so the menu bar surface is not an empty promise on first run.
    static var menuBarClock: WidgetDoc {
        let source = systemSource()
        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A6")!,
            name: "Menu clock",
            family: .menuBar,
            background: .none,
            elements: [
                Element(name: "Time", kind: .text,
                        frame: Frame(x: 0.03, y: 0.10, width: 0.52, height: 0.80),
                        style: Style(font: FontSpec(size: 12, weight: .semibold, design: .rounded),
                                     foreground: .text),
                        text: "18:42",
                        binding: DataBinding(sourceID: source.id, keyPath: "date.now",
                                             format: Format(kind: .date, dateStyle: .time),
                                             fallback: "--:--")),
                Element(name: "Day", kind: .text,
                        frame: Frame(x: 0.55, y: 0.16, width: 0.42, height: 0.68),
                        style: Style(font: FontSpec(size: 10, weight: .medium),
                                     foreground: .dim, alignment: .trailing),
                        text: "Tue",
                        binding: DataBinding(sourceID: source.id, keyPath: "date.now",
                                             format: Format(kind: .date, dateStyle: .shortWeekday),
                                             fallback: "—")),
            ],
            sources: [source])
    }

    // MARK: - Island

    /// Ships so the island is not an empty promise either.
    static var islandNow: WidgetDoc {
        let source = systemSource()
        return WidgetDoc(
            id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-0000000000A7")!,
            name: "Island",
            family: .island,
            background: Background(kind: .color, color: ColorSpec("#000000")),
            elements: [
                Element(name: "Time", kind: .text,
                        frame: Frame(x: 0.09, y: 0.16, width: 0.34, height: 0.68),
                        style: Style(font: FontSpec(size: 15, weight: .semibold, design: .rounded),
                                     foreground: .text),
                        text: "18:42",
                        binding: DataBinding(sourceID: source.id, keyPath: "date.now",
                                             format: Format(kind: .date, dateStyle: .time),
                                             fallback: "--:--")),
                Element(name: "Battery", kind: .bar,
                        frame: Frame(x: 0.47, y: 0.40, width: 0.24, height: 0.20),
                        style: Style(foreground: .accent,
                                     fill: ColorSpec(Palette.textDimHex, opacity: 0.3),
                                     gradientEnd: ColorSpec(Palette.accentAltHex)),
                        text: "0.9",
                        binding: DataBinding(sourceID: source.id, keyPath: "battery.percent",
                                             format: Format(kind: .percent), fallback: "0")),
                Element(name: "Percent", kind: .text,
                        frame: Frame(x: 0.73, y: 0.18, width: 0.20, height: 0.64),
                        style: Style(font: FontSpec(size: 12, weight: .medium, design: .rounded),
                                     foreground: .dim, alignment: .trailing),
                        text: "90%",
                        binding: DataBinding(sourceID: source.id, keyPath: "battery.percent",
                                             format: Format(kind: .percent), fallback: "—")),
            ],
            sources: [source])
    }
}
