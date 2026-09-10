import Foundation

/// The icons offered in the picker.
///
/// Choosing a symbol used to mean typing an exact SF Symbol name from memory
/// into a text field, with a tick that told you afterwards whether you had
/// guessed right. That is not a picker; it is a spelling test, and it made the
/// symbol element unusable for anyone who does not already know the catalogue.
///
/// Curated rather than exhaustive. SF Symbols has thousands of names and no
/// public API to enumerate them, and a widget wants a small, obvious set —
/// weather, time, the shape of a battery — not a browser for all of them. Every
/// name here is checked by a test against this machine's own symbol table, so a
/// name that stops existing fails the build rather than rendering as a question
/// mark on somebody's desktop.
enum SymbolCatalogue {
    static let groups: [(name: String, symbols: [String])] = [
        ("Time", ["clock", "clock.fill", "alarm", "alarm.fill", "stopwatch", "stopwatch.fill", "timer", "hourglass", "calendar", "calendar.badge.clock", "calendar.circle.fill", "deskclock.fill", "sunrise.fill", "sunset.fill", "moon.fill", "moon.stars.fill", "sun.max.fill", "sun.min.fill"]),
        ("Weather", ["cloud.fill", "cloud.rain.fill", "cloud.heavyrain.fill", "cloud.drizzle.fill", "cloud.snow.fill", "cloud.bolt.fill", "cloud.bolt.rain.fill", "cloud.sun.fill", "cloud.moon.fill", "cloud.fog.fill", "wind", "tornado", "humidity.fill", "thermometer.medium", "thermometer.sun.fill", "thermometer.snowflake", "snowflake", "drop.fill", "umbrella.fill", "rainbow"]),
        ("System", ["cpu", "cpu.fill", "memorychip", "memorychip.fill", "internaldrive", "internaldrive.fill", "externaldrive.fill", "opticaldiscdrive", "desktopcomputer", "laptopcomputer", "display", "macwindow", "gauge.with.dots.needle.67percent", "speedometer", "chart.bar.fill", "chart.line.uptrend.xyaxis", "chart.pie.fill", "waveform.path.ecg", "bolt.fill", "bolt.slash.fill"]),
        ("Battery", ["battery.100percent", "battery.75percent", "battery.50percent", "battery.25percent", "battery.0percent", "battery.100percent.bolt", "powerplug.fill", "bolt.batteryblock.fill", "minus.plus.batteryblock.fill"]),
        ("Network", ["wifi", "wifi.slash", "antenna.radiowaves.left.and.right", "network", "globe", "globe.americas.fill", "icloud.fill", "icloud.and.arrow.down.fill", "arrow.up.arrow.down", "arrow.down.circle.fill", "arrow.up.circle.fill", "dot.radiowaves.left.and.right", "personalhotspot", "cable.connector"]),
        ("Media", ["play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill", "speaker.wave.2.fill", "speaker.slash.fill", "music.note", "music.note.list", "headphones", "mic.fill", "video.fill", "camera.fill", "photo.fill", "film.fill", "tv.fill", "airpodspro", "hifispeaker.fill"]),
        ("People", ["person.fill", "person.2.fill", "person.crop.circle.fill", "envelope.fill", "message.fill", "bubble.left.fill", "phone.fill", "bell.fill", "bell.badge.fill", "paperplane.fill", "heart.fill", "hand.thumbsup.fill", "star.fill", "flag.fill"]),
        ("Places", ["house.fill", "building.2.fill", "location.fill", "location.north.fill", "map.fill", "mappin.circle.fill", "car.fill", "airplane", "tram.fill", "bicycle", "figure.walk", "figure.run", "leaf.fill", "tree.fill", "mountain.2.fill", "water.waves", "flame.fill", "sparkles"]),
        ("Work", ["folder.fill", "doc.fill", "doc.text.fill", "tray.fill", "archivebox.fill", "paperclip", "pencil", "trash.fill", "checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill", "info.circle.fill", "questionmark.circle.fill", "gearshape.fill", "slider.horizontal.3", "magnifyingglass", "lock.fill", "lock.open.fill", "key.fill", "creditcard.fill", "cart.fill", "bag.fill", "gift.fill", "dollarsign.circle.fill"]),
        ("Shapes", ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill", "app.fill", "capsule.fill", "rectangle.fill", "circle.grid.2x2.fill", "square.grid.2x2.fill", "chevron.right", "chevron.left", "chevron.up", "chevron.down", "arrow.right", "arrow.left", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.triangle.2.circlepath", "plus", "minus", "multiply", "divide", "equal", "percent", "number"]),
    ]

    /// Every symbol, flattened, in the order the groups are declared.
    static let all: [String] = groups.flatMap(\.symbols)

    /// Matches on the symbol's own name and on its group, so "weather" finds
    /// the clouds even though no symbol is called that.
    static func search(_ query: String) -> [(name: String, symbols: [String])] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return groups }
        return groups.compactMap { group in
            if group.name.lowercased().contains(needle) { return group }
            let hits = group.symbols.filter { $0.lowercased().contains(needle) }
            return hits.isEmpty ? nil : (name: group.name, symbols: hits)
        }
    }
}
