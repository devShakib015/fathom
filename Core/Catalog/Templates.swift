import Foundation

/// The designed layouts.
///
/// Each is a function from a theme and a family to a document, written against
/// `Kit` so it reads as a description of itself. The catalog's size is
/// templates × families × palettes, so this file is the one that grows — every
/// layout added here multiplies by twenty.
///
/// Sources use fixed ids per template so that two entries built from the same
/// layout produce the same bindings, and so a document duplicated out of the
/// catalog has a source the editor can already resolve.
enum Templates {

    private static func system() -> DataSource {
        DataSource(id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000001")!,
                   name: "System", kind: .system)
    }

    private static func openMeteo() -> DataSource {
        DataSource(id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000010")!,
                   name: "Open-Meteo", kind: .json,
                   url: "https://api.open-meteo.com/v1/forecast?latitude=25.2048&longitude=55.2708"
                      + "&current=temperature_2m,relative_humidity_2m,weather_code,is_day"
                      + "&daily=temperature_2m_max&forecast_days=7&timezone=auto")
    }

    private static func calendar() -> DataSource {
        DataSource(id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000020")!,
                   name: "Calendar", kind: .calendar)
    }

    private static func reminders() -> DataSource {
        DataSource(id: UUID(uuidString: "5B1F0F1A-0000-4000-A000-000000000021")!,
                   name: "Reminders", kind: .reminders)
    }

    /// The lookup that turns a WMO code into a symbol, shared by every weather
    /// layout so they cannot drift apart.
    private static let skySymbol =
        "if(current.is_day == 0, "
      + "map(value, 0, \"moon.stars.fill\", 1, \"moon.stars.fill\", 2, \"cloud.moon.fill\", "
      + "3, \"cloud.fill\", 45, \"cloud.fog.fill\", 51, \"cloud.drizzle.fill\", "
      + "61, \"cloud.rain.fill\", 65, \"cloud.heavyrain.fill\", 71, \"cloud.snow.fill\", "
      + "95, \"cloud.bolt.rain.fill\", \"cloud.fill\"), "
      + "map(value, 0, \"sun.max.fill\", 1, \"sun.max.fill\", 2, \"cloud.sun.fill\", "
      + "3, \"cloud.fill\", 45, \"cloud.fog.fill\", 51, \"cloud.drizzle.fill\", "
      + "61, \"cloud.rain.fill\", 65, \"cloud.heavyrain.fill\", 71, \"cloud.snow.fill\", "
      + "95, \"cloud.bolt.rain.fill\", \"cloud.fill\"))"

    // MARK: - The list

    static let all: [CatalogTemplate] = [
        clockStack, clockCentred, clockRail, dateBlock, timeAndDay,
        cpuRing, memoryRing, vitalsBars, uptimeCard, thermalCard,
        diskRing, diskDetail,
        batteryRing, batteryBar,
        networkRates,
        weatherNow, weatherSplit, weatherWeek,
        nextEvent, agendaList, remindersList,
        typographicTime, statPair,
        menuClock, menuVitals, menuBattery, menuWeather,
    ]

    // MARK: - Time

    static var clockStack: CatalogTemplate {
        CatalogTemplate(id: "clock-stack", name: "Clock stack", category: .time,
                        tags: ["clock", "time", "date", "weekday"],
                        families: [.small, .medium], needs: []) { theme, family in
            let s = system()
            let big: Double = family == .small ? 44 : 62
            return WidgetDoc(name: "Clock stack", family: family, background: theme.background,
                             elements: [
                Kit.text("Time", 0.07, 0.14, 0.86, 0.34, size: big, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, tracking: -1,
                         literal: "18:42", bind: Kit.time(s.id)),
                Kit.text("Weekday", 0.075, 0.52, 0.5, 0.12, size: family == .small ? 12 : 15,
                         weight: .medium, colour: theme.accentSpec,
                         literal: "Tuesday", bind: Kit.time(s.id, .weekday)),
                Kit.text("Date", 0.075, 0.66, 0.6, 0.12, size: family == .small ? 11 : 14,
                         colour: theme.dimSpec, literal: "8 Sep",
                         bind: Kit.time(s.id, .monthDay)),
            ], sources: [s])
        }
    }

    static var clockCentred: CatalogTemplate {
        CatalogTemplate(id: "clock-centred", name: "Centred clock", category: .minimal,
                        tags: ["clock", "time", "minimal", "big"],
                        families: [.small, .medium], needs: []) { theme, family in
            let s = system()
            return WidgetDoc(name: "Centred clock", family: family, background: theme.background,
                             elements: [
                Kit.text("Time", 0.05, 0.32, 0.9, 0.32, size: family == .small ? 46 : 76,
                         weight: .light, design: .rounded, colour: theme.textSpec,
                         align: .center, tracking: -1.5,
                         literal: "18:42", bind: Kit.time(s.id)),
                Kit.rule(0.36, 0.70, 0.28, 0.012, colour: theme.accent(0.5), width: 1),
                Kit.text("Day", 0.05, 0.75, 0.9, 0.1, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.4,
                         literal: "TUESDAY", bind: Kit.time(s.id, .weekday)),
            ], sources: [s])
        }
    }

    static var clockRail: CatalogTemplate {
        CatalogTemplate(id: "clock-rail", name: "Clock rail", category: .time,
                        tags: ["clock", "time", "accent", "bar"],
                        families: [.medium], needs: []) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Clock rail", family: .medium, background: theme.background,
                             elements: [
                Kit.shape("Rail", 0.05, 0.18, 0.022, 0.64, fill: theme.accentSpec, corner: 4),
                Kit.text("Time", 0.13, 0.16, 0.5, 0.34, size: 54, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, tracking: -1,
                         literal: "18:42", bind: Kit.time(s.id)),
                Kit.text("Weekday", 0.135, 0.56, 0.5, 0.13, size: 14, weight: .medium,
                         colour: theme.dimSpec, literal: "Tuesday",
                         bind: Kit.time(s.id, .weekday)),
                Kit.text("Date", 0.6, 0.16, 0.35, 0.14, size: 15, weight: .semibold,
                         colour: theme.accentSpec, align: .trailing,
                         literal: "8 Sep", bind: Kit.time(s.id, .monthDay)),
            ], sources: [s])
        }
    }

    static var dateBlock: CatalogTemplate {
        CatalogTemplate(id: "date-block", name: "Date block", category: .time,
                        tags: ["date", "calendar", "day", "month"],
                        families: [.small], needs: []) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Date block", family: .small, background: theme.background,
                             elements: [
                Kit.text("Month", 0.05, 0.14, 0.9, 0.12, size: 12, weight: .semibold,
                         colour: theme.accentSpec, align: .center, tracking: 2,
                         literal: "SEPTEMBER", bind: Kit.time(s.id, .month)),
                Kit.text("Day", 0.05, 0.27, 0.9, 0.38, size: 68, weight: .bold,
                         design: .rounded, colour: theme.textSpec, align: .center, tracking: -2,
                         literal: "8", bind: Kit.time(s.id, .day)),
                Kit.text("Weekday", 0.05, 0.70, 0.9, 0.12, size: 13, weight: .medium,
                         colour: theme.dimSpec, align: .center,
                         literal: "Tuesday", bind: Kit.time(s.id, .weekday)),
            ], sources: [s])
        }
    }

    static var timeAndDay: CatalogTemplate {
        CatalogTemplate(id: "time-and-day", name: "Time and day", category: .time,
                        tags: ["clock", "date", "split"],
                        families: [.medium], needs: []) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Time and day", family: .medium, background: theme.background,
                             elements: [
                Kit.text("Time", 0.05, 0.24, 0.42, 0.34, size: 52, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .center, tracking: -1,
                         literal: "18:42", bind: Kit.time(s.id)),
                Kit.rule(0.50, 0.20, 0.012, 0.6, colour: theme.dim(0.3), width: 1),
                Kit.text("Day number", 0.55, 0.2, 0.4, 0.3, size: 46, weight: .bold,
                         design: .rounded, colour: theme.accentSpec, align: .center,
                         literal: "8", bind: Kit.time(s.id, .day)),
                Kit.text("Weekday", 0.55, 0.56, 0.4, 0.13, size: 13, weight: .medium,
                         colour: theme.dimSpec, align: .center,
                         literal: "Tuesday", bind: Kit.time(s.id, .weekday)),
            ], sources: [s])
        }
    }

    static var typographicTime: CatalogTemplate {
        CatalogTemplate(id: "typographic-time", name: "Hour and minute", category: .minimal,
                        tags: ["minimal", "type", "stacked", "clock"],
                        families: [.small], needs: []) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Hour and minute", family: .small, background: theme.background,
                             elements: [
                Kit.text("Hour", 0.06, 0.10, 0.88, 0.40, size: 78, weight: .bold,
                         design: .rounded, colour: theme.textSpec, align: .leading, tracking: -3,
                         literal: "18", bind: Kit.time(s.id, .hour)),
                Kit.text("Minute", 0.06, 0.50, 0.88, 0.40, size: 78, weight: .bold,
                         design: .rounded, colour: theme.accentSpec, align: .trailing, tracking: -3,
                         literal: "42", bind: Kit.time(s.id, .minute)),
            ], sources: [s])
        }
    }

    // MARK: - System

    static var cpuRing: CatalogTemplate {
        CatalogTemplate(id: "cpu-ring", name: "CPU ring", category: .system,
                        tags: ["cpu", "processor", "load", "ring"],
                        families: [.small], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "CPU ring", family: .small, background: theme.background,
                             elements: [
                Kit.arc("Ring", 0.18, 0.14, 0.64, 0.64, colour: theme.accentSpec,
                        track: theme.accent(0.15), width: 9, gradient: theme.accentAltSpec,
                        bind: Kit.percent(s.id, "cpu.usage")),
                Kit.text("Value", 0.18, 0.36, 0.64, 0.2, size: 22, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .center,
                         literal: "43%", bind: Kit.percent(s.id, "cpu.usage")),
                Kit.text("Label", 0.05, 0.82, 0.9, 0.11, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "CPU"),
            ], sources: [s])
        }
    }

    static var memoryRing: CatalogTemplate {
        CatalogTemplate(id: "memory-ring", name: "Memory ring", category: .system,
                        tags: ["memory", "ram", "ring", "gauge"],
                        families: [.small], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Memory ring", family: .small, background: theme.background,
                             elements: [
                // An open gauge rather than a closed ring: three quarters of a
                // turn reads as a dial, and leaves room for a label inside.
                Kit.arc("Gauge", 0.14, 0.12, 0.72, 0.72, colour: theme.accentAltSpec,
                        track: theme.dim(0.2), width: 10, sweep: 270, start: 225,
                        bind: Kit.percent(s.id, "memory.usedFraction")),
                Kit.text("Value", 0.18, 0.35, 0.64, 0.2, size: 22, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .center,
                         literal: "76%", bind: Kit.percent(s.id, "memory.usedFraction")),
                Kit.text("Used", 0.18, 0.55, 0.64, 0.12, size: 10,
                         colour: theme.dimSpec, align: .center,
                         literal: "6.5 GB", bind: Kit.bytes(s.id, "memory.used")),
                Kit.text("Label", 0.05, 0.83, 0.9, 0.11, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "MEMORY"),
            ], sources: [s])
        }
    }

    static var vitalsBars: CatalogTemplate {
        CatalogTemplate(id: "vitals-bars", name: "Mac vitals", category: .system,
                        tags: ["cpu", "memory", "disk", "bars", "dashboard"],
                        families: [.medium], needs: [.system]) { theme, _ in
            let s = system()
            func row(_ label: String, _ y: Double, _ barPath: String,
                     _ valuePath: String, _ format: Format, _ tint: ColorSpec,
                     _ sample: String, _ level: String) -> [Element] {
                [
                    Kit.text("\(label) label", 0.05, y - 0.055, 0.17, 0.11, size: 11,
                             weight: .medium, colour: theme.dimSpec, literal: label),
                    Kit.bar("\(label) bar", 0.24, y - 0.022, 0.48, 0.045,
                            colour: tint, track: ColorSpec(tint.hex, opacity: 0.15),
                            literal: level, bind: Kit.percent(s.id, barPath)),
                    Kit.text("\(label) value", 0.74, y - 0.062, 0.21, 0.12, size: 11,
                             weight: .semibold, colour: theme.textSpec, align: .trailing,
                             literal: sample, bind: Kit.bind(s.id, valuePath, format)),
                ]
            }
            var elements = [
                Kit.text("Title", 0.05, 0.06, 0.45, 0.11, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "THIS MAC"),
                Kit.text("Uptime", 0.52, 0.06, 0.43, 0.11, size: 9, colour: theme.dimSpec,
                         align: .trailing, literal: "up 8h 14m",
                         bind: Kit.bind(s.id, "system.uptime",
                                        Format(kind: .duration, prefix: "up "), fallback: "up —")),
            ]
            elements += row("CPU", 0.34, "cpu.usage", "cpu.usage",
                            Format(kind: .percent), theme.accentSpec, "43%", "0.43")
            elements += row("Memory", 0.58, "memory.usedFraction", "memory.usedFraction",
                            Format(kind: .percent), theme.accentAltSpec, "76%", "0.76")
            elements += row("Disk", 0.82, "disk.usedFraction", "disk.free",
                            Format(kind: .bytes), theme.accentSpec, "221 GB", "0.55")
            return WidgetDoc(name: "Mac vitals", family: .medium, background: theme.background,
                             elements: elements, sources: [s])
        }
    }

    static var uptimeCard: CatalogTemplate {
        CatalogTemplate(id: "uptime-card", name: "Uptime", category: .system,
                        tags: ["uptime", "boot", "since"],
                        families: [.small, .medium], needs: [.system]) { theme, family in
            let s = system()
            return WidgetDoc(name: "Uptime", family: family, background: theme.background,
                             elements: [
                Kit.symbol("Icon", 0.06, 0.13, family == .small ? 0.2 : 0.1, 0.2,
                           colour: theme.accentSpec, align: .leading, literal: "power"),
                Kit.text("Value", 0.05, 0.38, 0.9, 0.26, size: family == .small ? 30 : 40,
                         weight: .semibold, design: .rounded, colour: theme.textSpec,
                         literal: "8h 14m",
                         bind: Kit.bind(s.id, "system.uptime", Format(kind: .duration))),
                Kit.text("Label", 0.05, 0.66, 0.9, 0.12, size: 11, colour: theme.dimSpec,
                         literal: "since —",
                         bind: Kit.bind(s.id, "system.bootedAt",
                                        Format(kind: .date, dateStyle: .time, prefix: "since "),
                                        fallback: "since —")),
            ], sources: [s])
        }
    }

    static var thermalCard: CatalogTemplate {
        CatalogTemplate(id: "thermal-card", name: "Thermal state", category: .system,
                        tags: ["thermal", "heat", "temperature", "status"],
                        families: [.small], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Thermal state", family: .small, background: theme.background,
                             elements: [
                // The symbol and the word come from the same field through two
                // different lookups, so they can never disagree.
                Kit.symbol("Icon", 0.34, 0.16, 0.32, 0.26, colour: theme.accentSpec,
                           literal: "thermometer.medium",
                           bind: Kit.bind(s.id, "system.thermal", Format(kind: .text),
                                          fallback: "thermometer.medium",
                                          expression: "map(value, \"nominal\", \"thermometer.low\", "
                                                    + "\"fair\", \"thermometer.medium\", "
                                                    + "\"serious\", \"thermometer.high\", "
                                                    + "\"critical\", \"flame.fill\", \"thermometer.medium\")")),
                Kit.text("State", 0.05, 0.48, 0.9, 0.18, size: 20, weight: .semibold,
                         colour: theme.textSpec, align: .center, literal: "Nominal",
                         bind: Kit.bind(s.id, "system.thermal", Format(kind: .text),
                                        expression: "map(value, \"nominal\", \"Nominal\", "
                                                  + "\"fair\", \"Warm\", \"serious\", \"Hot\", "
                                                  + "\"critical\", \"Throttling\", \"Unknown\")")),
                Kit.text("Label", 0.05, 0.70, 0.9, 0.12, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2,
                         literal: "THERMAL STATE"),
            ], sources: [s])
        }
    }

    // MARK: - Storage

    static var diskRing: CatalogTemplate {
        CatalogTemplate(id: "disk-ring", name: "Disk ring", category: .storage,
                        tags: ["disk", "storage", "free", "ring"],
                        families: [.small], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Disk ring", family: .small, background: theme.background,
                             elements: [
                Kit.arc("Ring", 0.16, 0.10, 0.68, 0.68, colour: theme.accentSpec,
                        track: theme.accent(0.15), width: 9,
                        bind: Kit.percent(s.id, "disk.usedFraction")),
                Kit.text("Free", 0.18, 0.33, 0.64, 0.2, size: 19, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .center,
                         literal: "221 GB", bind: Kit.bytes(s.id, "disk.free")),
                Kit.text("Caption", 0.18, 0.52, 0.64, 0.12, size: 10, colour: theme.dimSpec,
                         align: .center, literal: "free"),
                Kit.text("Label", 0.05, 0.82, 0.9, 0.11, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "STORAGE"),
            ], sources: [s])
        }
    }

    static var diskDetail: CatalogTemplate {
        CatalogTemplate(id: "disk-detail", name: "Storage detail", category: .storage,
                        tags: ["disk", "storage", "used", "total", "bar"],
                        families: [.medium], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Storage detail", family: .medium, background: theme.background,
                             elements: [
                Kit.symbol("Icon", 0.05, 0.14, 0.1, 0.2, colour: theme.accentSpec,
                           align: .leading, literal: "internaldrive.fill"),
                Kit.text("Free", 0.18, 0.13, 0.5, 0.22, size: 30, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "221 GB",
                         bind: Kit.bytes(s.id, "disk.free")),
                Kit.text("Caption", 0.185, 0.37, 0.5, 0.12, size: 11, colour: theme.dimSpec,
                         literal: "free of 494 GB",
                         bind: Kit.bind(s.id, "disk.total",
                                        Format(kind: .bytes, prefix: "free of "),
                                        fallback: "free")),
                Kit.bar("Bar", 0.05, 0.62, 0.9, 0.07, colour: theme.accentSpec,
                        track: theme.dim(0.22), gradient: theme.accentAltSpec,
                        bind: Kit.percent(s.id, "disk.usedFraction")),
                Kit.text("Used", 0.05, 0.75, 0.44, 0.12, size: 10, colour: theme.dimSpec,
                         literal: "273 GB used", bind: Kit.bind(s.id, "disk.used",
                                                           Format(kind: .bytes, suffix: " used"))),
                Kit.text("Percent", 0.51, 0.75, 0.44, 0.12, size: 10, colour: theme.dimSpec,
                         align: .trailing, literal: "55%",
                         bind: Kit.percent(s.id, "disk.usedFraction")),
            ], sources: [s])
        }
    }

    // MARK: - Battery

    static var batteryRing: CatalogTemplate {
        CatalogTemplate(id: "battery-ring", name: "Battery ring", category: .battery,
                        tags: ["battery", "charge", "ring", "power"],
                        families: [.small], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Battery ring", family: .small, background: theme.background,
                             elements: [
                Kit.arc("Ring", 0.16, 0.10, 0.68, 0.68, colour: theme.accentSpec,
                        track: theme.accent(0.15), width: 9,
                        bind: Kit.percent(s.id, "battery.percent")),
                Kit.text("Value", 0.18, 0.33, 0.64, 0.2, size: 24, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .center,
                         literal: "90%", bind: Kit.percent(s.id, "battery.percent")),
                // Only shown while charging, which is the whole point of
                // conditional visibility: no second document for the plugged-in
                // case.
                Element(name: "Bolt", kind: .symbol,
                        frame: Frame(x: 0.44, y: 0.53, width: 0.12, height: 0.12),
                        style: Style(foreground: theme.accentAltSpec, alignment: .center),
                        text: "bolt.fill",
                        binding: nil,
                        visibleWhen: "battery.isCharging"),
                Kit.text("Label", 0.05, 0.82, 0.9, 0.11, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "BATTERY"),
            ], sources: [s])
        }
    }

    static var batteryBar: CatalogTemplate {
        CatalogTemplate(id: "battery-bar", name: "Battery bar", category: .battery,
                        tags: ["battery", "charge", "bar", "remaining"],
                        families: [.medium], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Battery bar", family: .medium, background: theme.background,
                             elements: [
                Kit.text("Value", 0.05, 0.16, 0.5, 0.28, size: 44, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "90%",
                         bind: Kit.percent(s.id, "battery.percent")),
                Kit.symbol("Bolt", 0.86, 0.18, 0.1, 0.16, colour: theme.accentAltSpec,
                           literal: "bolt.fill"),
                Kit.bar("Bar", 0.05, 0.55, 0.9, 0.08, colour: theme.accentSpec,
                        track: theme.dim(0.22), gradient: theme.accentAltSpec,
                        bind: Kit.percent(s.id, "battery.percent")),
                Kit.text("Remaining", 0.05, 0.70, 0.9, 0.13, size: 11, colour: theme.dimSpec,
                         literal: "3h 40m remaining",
                         bind: Kit.bind(s.id, "battery.minutesRemaining",
                                        Format(kind: .duration, suffix: " remaining"),
                                        fallback: "on power",
                                        expression: "if(value > 0, value * 60, null)")),
            ], sources: [s])
        }
    }

    // MARK: - Network

    static var networkRates: CatalogTemplate {
        CatalogTemplate(id: "network-rates", name: "Network", category: .network,
                        tags: ["network", "throughput", "download", "upload"],
                        families: [.medium], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Network", family: .medium, background: theme.background,
                             elements: [
                Kit.text("Title", 0.05, 0.08, 0.9, 0.1, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "NETWORK"),
                Kit.symbol("Down", 0.05, 0.28, 0.08, 0.14, colour: theme.accentSpec,
                           align: .leading, literal: "arrow.down"),
                Kit.text("In", 0.15, 0.24, 0.32, 0.2, size: 22, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "1.7 KB/s",
                         bind: Kit.bind(s.id, "network.inPerSecond",
                                        Format(kind: .bytes, suffix: "/s"), fallback: "—")),
                Kit.symbol("Up", 0.05, 0.58, 0.08, 0.14, colour: theme.accentAltSpec,
                           align: .leading, literal: "arrow.up"),
                Kit.text("Out", 0.15, 0.54, 0.32, 0.2, size: 22, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "337 B/s",
                         bind: Kit.bind(s.id, "network.outPerSecond",
                                        Format(kind: .bytes, suffix: "/s"), fallback: "—")),
                Kit.rule(0.52, 0.2, 0.012, 0.6, colour: theme.dim(0.28), width: 1),
                Kit.text("Total label", 0.58, 0.26, 0.37, 0.1, size: 9, weight: .medium,
                         colour: theme.dimSpec, tracking: 1, literal: "SINCE BOOT"),
                Kit.text("Total in", 0.58, 0.38, 0.37, 0.14, size: 13, weight: .medium,
                         colour: theme.textSpec, literal: "↓ 2.9 GB",
                         bind: Kit.bind(s.id, "network.totalIn",
                                        Format(kind: .bytes, prefix: "↓ "))),
                Kit.text("Total out", 0.58, 0.54, 0.37, 0.14, size: 13, weight: .medium,
                         colour: theme.dimSpec, literal: "↑ 3.7 GB",
                         bind: Kit.bind(s.id, "network.totalOut",
                                        Format(kind: .bytes, prefix: "↑ "))),
            ], sources: [s])
        }
    }

    // MARK: - Weather

    static var weatherNow: CatalogTemplate {
        CatalogTemplate(id: "weather-now", name: "Weather now", category: .weather,
                        tags: ["weather", "temperature", "sky", "outside"],
                        families: [.small], needs: [.json]) { theme, _ in
            let w = openMeteo()
            return WidgetDoc(name: "Weather now", family: .small, background: theme.background,
                             elements: [
                Kit.symbol("Sky", 0.06, 0.10, 0.3, 0.24, colour: theme.accentSpec,
                           align: .leading, literal: "sun.max.fill",
                           bind: Kit.bind(w.id, "current.weather_code", Format(kind: .text),
                                          fallback: "questionmark", expression: skySymbol)),
                Kit.text("Temp", 0.05, 0.40, 0.9, 0.28, size: 42, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, tracking: -1,
                         literal: "36°",
                         bind: Kit.bind(w.id, "current.temperature_2m",
                                        Format(kind: .number, suffix: "°"))),
                Kit.text("Humidity", 0.055, 0.72, 0.88, 0.12, size: 11, colour: theme.dimSpec,
                         literal: "humidity 55%",
                         bind: Kit.bind(w.id, "current.relative_humidity_2m",
                                        Format(kind: .percent, prefix: "humidity "),
                                        fallback: "humidity —")),
            ], sources: [w])
        }
    }

    static var weatherSplit: CatalogTemplate {
        CatalogTemplate(id: "weather-split", name: "Weather split", category: .weather,
                        tags: ["weather", "temperature", "humidity", "forecast"],
                        families: [.medium], needs: [.json]) { theme, _ in
            let w = openMeteo()
            return WidgetDoc(name: "Weather split", family: .medium, background: theme.background,
                             elements: [
                Kit.symbol("Sky", 0.045, 0.19, 0.095, 0.25, colour: theme.accentSpec,
                           literal: "sun.max.fill",
                           bind: Kit.bind(w.id, "current.weather_code", Format(kind: .text),
                                          fallback: "questionmark", expression: skySymbol)),
                Kit.text("Temp", 0.165, 0.11, 0.33, 0.35, size: 40, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, tracking: -1, literal: "36°",
                         bind: Kit.bind(w.id, "current.temperature_2m",
                                        Format(kind: .number, precision: 1, suffix: "°"))),
                Kit.text("Observed", 0.17, 0.53, 0.33, 0.13, size: 11, colour: theme.dimSpec,
                         literal: "at 17:45",
                         bind: Kit.bind(w.id, "current.time",
                                        Format(kind: .date, dateStyle: .time, prefix: "at "),
                                        fallback: "offline")),
                Kit.rule(0.515, 0.18, 0.012, 0.64, colour: theme.dim(0.25), width: 1),
                Kit.spark("Week ahead", 0.565, 0.17, 0.39, 0.30,
                          colour: theme.accentAltSpec,
                          fill: ColorSpec(theme.accentAlt, opacity: 0.28),
                          bind: Kit.bind(w.id, "daily.temperature_2m_max",
                                         Format(kind: .text), fallback: "0")),
                Kit.text("Caption", 0.57, 0.49, 0.39, 0.11, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 0.8, literal: "SEVEN-DAY HIGH"),
                Kit.text("Humidity", 0.57, 0.675, 0.39, 0.15, size: 12, weight: .medium,
                         colour: theme.textSpec, literal: "humidity 55%",
                         bind: Kit.bind(w.id, "current.relative_humidity_2m",
                                        Format(kind: .percent, prefix: "humidity "),
                                        fallback: "humidity —")),
            ], sources: [w])
        }
    }

    static var weatherWeek: CatalogTemplate {
        CatalogTemplate(id: "weather-week", name: "Week ahead", category: .weather,
                        tags: ["weather", "forecast", "week", "columns", "chart"],
                        families: [.large], needs: [.json]) { theme, _ in
            let w = openMeteo()
            let highs = "field(\"daily.temperature_2m_max\")"
            return WidgetDoc(name: "Week ahead", family: .large, background: theme.background,
                             elements: [
                Kit.text("Caption", 0.06, 0.055, 0.5, 0.05, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "WEEK AHEAD"),
                Kit.text("Now", 0.055, 0.10, 0.5, 0.13, size: 34, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "36°",
                         bind: Kit.bind(w.id, "current.temperature_2m",
                                        Format(kind: .number, suffix: "°"))),
                Kit.symbol("Sky", 0.79, 0.095, 0.13, 0.10, colour: theme.accentSpec,
                           literal: "sun.max.fill",
                           bind: Kit.bind(w.id, "current.weather_code", Format(kind: .text),
                                          fallback: "questionmark", expression: skySymbol)),
                Kit.rule(0.06, 0.26, 0.88, 0.01, colour: theme.dim(0.22), width: 1),
                Kit.repeater("Seven days", 0.05, 0.32, 0.90, 0.56, spacing: 3,
                             bind: Kit.bind(w.id, "daily.time", Format(kind: .text), fallback: ""),
                             children: [
                    Kit.text("High", 0, 0, 1, 0.13, size: 10, weight: .semibold,
                             colour: theme.textSpec, align: .center, literal: "41°",
                             bind: Kit.bind(w.id, "", Format(kind: .number, suffix: "°"),
                                            expression: "at(\(highs), index)")),
                    Kit.bar("Column", 0.26, 0.16, 0.48, 0.68, colour: theme.accentSpec,
                            track: theme.accent(0.12), corner: 4, gradient: theme.accentAltSpec,
                            bind: Kit.bind(w.id, "", Format(kind: .percent), fallback: "0",
                                           expression: "coalesce((at(\(highs), index) - lowest(\(highs))) "
                                                     + "/ (highest(\(highs)) - lowest(\(highs))), 0.5) "
                                                     + "* 0.82 + 0.18")),
                    Kit.text("Day", 0, 0.87, 1, 0.13, size: 9, weight: .medium,
                             colour: theme.dimSpec, align: .center, literal: "Tue",
                             bind: Kit.bind(w.id, "",
                                            Format(kind: .date, dateStyle: .shortWeekday))),
                ]),
                Kit.text("Footer", 0.06, 0.925, 0.88, 0.05, size: 8, colour: theme.dimSpec,
                         align: .center, literal: "Open-Meteo · refreshed every 64 s"),
            ], sources: [w])
        }
    }

    // MARK: - Calendar

    static var nextEvent: CatalogTemplate {
        CatalogTemplate(id: "next-event", name: "Next event", category: .calendar,
                        tags: ["calendar", "meeting", "next", "agenda"],
                        families: [.small, .medium], needs: [.calendar]) { theme, family in
            let c = calendar()
            return WidgetDoc(name: "Next event", family: family, background: theme.background,
                             elements: [
                Kit.text("Caption", 0.06, 0.08, 0.88, 0.1, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "UP NEXT"),
                Kit.text("Title", 0.06, 0.22, 0.88, family == .small ? 0.3 : 0.26,
                         size: family == .small ? 15 : 20, weight: .semibold,
                         colour: theme.textSpec, lines: 2, literal: "Nothing scheduled",
                         bind: Kit.bind(c.id, "next.title", Format(kind: .text),
                                        fallback: "Nothing scheduled")),
                Kit.text("Time", 0.06, family == .small ? 0.56 : 0.54, 0.88, 0.16,
                         size: family == .small ? 20 : 26, weight: .semibold, design: .rounded,
                         colour: theme.accentSpec, literal: "14:30",
                         bind: Kit.bind(c.id, "next.startsAt",
                                        Format(kind: .date, dateStyle: .time), fallback: "—")),
                Element(name: "Countdown", kind: .text,
                        frame: Frame(x: 0.06, y: family == .small ? 0.74 : 0.72,
                                     width: 0.88, height: 0.13),
                        style: Style(font: FontSpec(size: 11), foreground: theme.dimSpec),
                        text: "in 25m",
                        binding: Kit.bind(c.id, "next.minutesUntil",
                                          Format(kind: .duration, prefix: "in "),
                                          fallback: "", expression: "value * 60"),
                        visibleWhen: "authorised"),
                Element(name: "Needs access", kind: .text,
                        frame: Frame(x: 0.06, y: 0.74, width: 0.88, height: 0.14),
                        style: Style(font: FontSpec(size: 10), foreground: theme.accentAltSpec,
                                     lineLimit: 2),
                        text: "Fathom needs calendar access",
                        binding: nil,
                        visibleWhen: "!authorised"),
            ], sources: [c])
        }
    }

    static var agendaList: CatalogTemplate {
        CatalogTemplate(id: "agenda-list", name: "Agenda", category: .calendar,
                        tags: ["calendar", "agenda", "list", "today"],
                        families: [.large], needs: [.calendar]) { theme, _ in
            let c = calendar()
            return WidgetDoc(name: "Agenda", family: .large, background: theme.background,
                             elements: [
                Kit.text("Caption", 0.07, 0.055, 0.6, 0.05, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "NEXT 24 HOURS"),
                Kit.text("Count", 0.6, 0.05, 0.33, 0.06, size: 11, weight: .semibold,
                         colour: theme.accentSpec, align: .trailing, literal: "3 events",
                         bind: Kit.bind(c.id, "count",
                                        Format(kind: .number, suffix: " events"), fallback: "—")),
                Kit.rule(0.07, 0.12, 0.86, 0.008, colour: theme.dim(0.22), width: 1),
                Kit.repeater("Events", 0.07, 0.16, 0.86, 0.78, spacing: 5,
                             bind: Kit.bind(c.id, "events", Format(kind: .text), fallback: ""),
                             children: [
                    Kit.shape("Chip", 0, 0.1, 0.012, 0.8, fill: theme.accentSpec, corner: 2),
                    Kit.text("Time", 0.05, 0.08, 0.24, 0.4, size: 12, weight: .semibold,
                             design: .rounded, colour: theme.accentSpec, literal: "14:30",
                             bind: Kit.bind(c.id, "startsAt",
                                            Format(kind: .date, dateStyle: .time))),
                    Kit.text("Title", 0.05, 0.48, 0.94, 0.42, size: 12,
                             colour: theme.textSpec, literal: "Design review",
                             bind: Kit.bind(c.id, "title", Format(kind: .text))),
                ]),
            ], sources: [c])
        }
    }

    static var remindersList: CatalogTemplate {
        CatalogTemplate(id: "reminders-list", name: "Reminders", category: .calendar,
                        tags: ["reminders", "todo", "due", "list"],
                        families: [.medium, .large], needs: [.reminders]) { theme, family in
            let r = reminders()
            return WidgetDoc(name: "Reminders", family: family, background: theme.background,
                             elements: [
                Kit.text("Caption", 0.07, 0.07, 0.6, 0.09, size: 9, weight: .semibold,
                         colour: theme.dimSpec, tracking: 1.2, literal: "DUE"),
                Kit.text("Count", 0.6, 0.065, 0.33, 0.1, size: 11, weight: .semibold,
                         colour: theme.accentSpec, align: .trailing, literal: "4",
                         bind: Kit.bind(r.id, "count", Format(kind: .number), fallback: "—")),
                Kit.repeater("Items", 0.07, 0.22, 0.86, family == .medium ? 0.68 : 0.72,
                             spacing: 4,
                             bind: Kit.bind(r.id, "items", Format(kind: .text), fallback: ""),
                             children: [
                    Kit.symbol("Dot", 0, 0.15, 0.05, 0.7, colour: theme.accentSpec,
                               align: .leading, literal: "circle"),
                    Kit.text("Title", 0.08, 0.1, 0.92, 0.8, size: 12,
                             colour: theme.textSpec, literal: "Send the invoice",
                             bind: Kit.bind(r.id, "title", Format(kind: .text))),
                ]),
            ], sources: [r])
        }
    }

    // MARK: - Minimal

    static var statPair: CatalogTemplate {
        CatalogTemplate(id: "stat-pair", name: "Two numbers", category: .minimal,
                        tags: ["minimal", "stats", "pair", "dashboard"],
                        families: [.medium], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Two numbers", family: .medium, background: theme.background,
                             elements: [
                Kit.text("Left value", 0.06, 0.24, 0.4, 0.3, size: 46, weight: .bold,
                         design: .rounded, colour: theme.accentSpec, align: .center, tracking: -1.5,
                         literal: "43%", bind: Kit.percent(s.id, "cpu.usage")),
                Kit.text("Left label", 0.06, 0.60, 0.4, 0.12, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "CPU"),
                Kit.rule(0.495, 0.26, 0.012, 0.48, colour: theme.dim(0.25), width: 1),
                Kit.text("Right value", 0.54, 0.24, 0.4, 0.3, size: 46, weight: .bold,
                         design: .rounded, colour: theme.accentAltSpec, align: .center, tracking: -1.5,
                         literal: "76%", bind: Kit.percent(s.id, "memory.usedFraction")),
                Kit.text("Right label", 0.54, 0.60, 0.4, 0.12, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .center, tracking: 1.2, literal: "MEMORY"),
            ], sources: [s])
        }
    }

    // MARK: - Menu bar
    //
    // Twenty-two points tall, which is not much: one or two values, nothing
    // decorative, type at eleven or twelve points. A design that works at 164
    // square does not survive here, which is why the menu bar is a family of
    // its own rather than a scaling problem.

    static var menuClock: CatalogTemplate {
        CatalogTemplate(id: "menu-clock", name: "Clock", category: .time,
                        tags: ["menu bar", "clock", "time", "date"],
                        families: [.menuBar], needs: []) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Clock", family: .menuBar, background: theme.background,
                             elements: [
                Kit.text("Time", 0.03, 0.10, 0.52, 0.80, size: 12, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "18:42",
                         bind: Kit.time(s.id)),
                Kit.text("Day", 0.55, 0.16, 0.42, 0.68, size: 10, weight: .medium,
                         colour: theme.dimSpec, align: .trailing, literal: "Tue",
                         bind: Kit.time(s.id, .shortWeekday)),
            ], sources: [s])
        }
    }

    static var menuVitals: CatalogTemplate {
        CatalogTemplate(id: "menu-vitals", name: "CPU and memory", category: .system,
                        tags: ["menu bar", "cpu", "memory", "load"],
                        families: [.menuBar], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "CPU and memory", family: .menuBar, background: theme.background,
                             elements: [
                Kit.text("CPU label", 0.02, 0.18, 0.14, 0.66, size: 9, weight: .semibold,
                         colour: theme.dimSpec, literal: "CPU"),
                Kit.text("CPU", 0.17, 0.12, 0.22, 0.78, size: 11, weight: .semibold,
                         design: .rounded, colour: theme.accentSpec, literal: "43%",
                         bind: Kit.percent(s.id, "cpu.usage")),
                Kit.text("Memory label", 0.44, 0.18, 0.16, 0.66, size: 9, weight: .semibold,
                         colour: theme.dimSpec, literal: "MEM"),
                Kit.text("Memory", 0.61, 0.12, 0.22, 0.78, size: 11, weight: .semibold,
                         design: .rounded, colour: theme.accentAltSpec, literal: "76%",
                         bind: Kit.percent(s.id, "memory.usedFraction")),
            ], sources: [s])
        }
    }

    static var menuBattery: CatalogTemplate {
        CatalogTemplate(id: "menu-battery", name: "Battery", category: .battery,
                        tags: ["menu bar", "battery", "charge"],
                        families: [.menuBar], needs: [.system]) { theme, _ in
            let s = system()
            return WidgetDoc(name: "Battery", family: .menuBar, background: theme.background,
                             elements: [
                Kit.bar("Level", 0.03, 0.34, 0.52, 0.32, colour: theme.accentSpec,
                        track: theme.dim(0.28), gradient: theme.accentAltSpec,
                        literal: "0.9", bind: Kit.percent(s.id, "battery.percent")),
                Kit.text("Percent", 0.58, 0.10, 0.30, 0.80, size: 11, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, align: .trailing,
                         literal: "90%", bind: Kit.percent(s.id, "battery.percent")),
                Element(name: "Bolt", kind: .symbol,
                        frame: Frame(x: 0.90, y: 0.22, width: 0.08, height: 0.56),
                        style: Style(foreground: theme.accentAltSpec, alignment: .center),
                        text: "bolt.fill",
                        binding: nil,
                        visibleWhen: "battery.isCharging"),
            ], sources: [s])
        }
    }

    static var menuWeather: CatalogTemplate {
        CatalogTemplate(id: "menu-weather", name: "Weather", category: .weather,
                        tags: ["menu bar", "weather", "temperature"],
                        families: [.menuBar], needs: [.json]) { theme, _ in
            let w = openMeteo()
            return WidgetDoc(name: "Weather", family: .menuBar, background: theme.background,
                             elements: [
                Kit.symbol("Sky", 0.02, 0.14, 0.16, 0.72, colour: theme.accentSpec,
                           literal: "sun.max.fill",
                           bind: Kit.bind(w.id, "current.weather_code", Format(kind: .text),
                                          fallback: "questionmark", expression: skySymbol)),
                Kit.text("Temp", 0.21, 0.10, 0.44, 0.80, size: 12, weight: .semibold,
                         design: .rounded, colour: theme.textSpec, literal: "36°",
                         bind: Kit.bind(w.id, "current.temperature_2m",
                                        Format(kind: .number, suffix: "°"))),
                Kit.text("Humidity", 0.66, 0.16, 0.32, 0.68, size: 9, weight: .medium,
                         colour: theme.dimSpec, align: .trailing, literal: "55%",
                         bind: Kit.percent(w.id, "current.relative_humidity_2m")),
            ], sources: [w])
        }
    }
}
