import Foundation
import IOKit.ps

/// The values macOS already knows, offered as a data source so that a widget
/// bound to the clock and a widget bound to a weather endpoint are built the
/// same way. There is no separate "clock element".
///
/// Read fresh on every timeline reload. The extension is usually a brand new
/// process by then, so there is nothing to cache and nothing to invalidate.
enum SystemSource {

    /// Every branch this source can produce, so a caller can say which it
    /// wants without hardcoding the list.
    static let branchNames = ["date", "battery", "disk", "cpu", "memory",
                              "network", "system", "devices", "place"]

    /// `needed` nil means all of them, which is what a caller that cannot tell
    /// should ask for — a missing branch reads as a missing value, and that is
    /// a worse failure than a wasted `statfs`.
    static func snapshot(now: Date = Date(), needed: Set<String>? = nil) -> DataValue {
        func wants(_ name: String) -> Bool { needed?.contains(name) ?? true }

        // Counters are read once and stored, so the next reload can turn them
        // into rates. Done here rather than per-branch so one reload writes one
        // sample no matter how many branches ask for a rate.
        // Counters are read, and written back, only when something asks for a
        // rate. This used to happen on every resolve: an atomic write to the
        // shared store every few seconds, forever, for designs that never
        // mentioned the CPU or the network.
        let needsRates = wants("cpu") || wants("network")
        let previous = needsRates ? CounterSamples.previous() : nil
        let ticks = needsRates ? HostMetrics.cpuTicks() : nil
        let traffic = needsRates ? HostMetrics.networkBytes() : (received: 0.0, sent: 0.0)

        if needsRates {
            var counters: [String: Double] = [
                "net.in": traffic.received,
                "net.out": traffic.sent,
            ]
            if let ticks {
                counters["cpu.user"] = ticks.user
                counters["cpu.system"] = ticks.system
                counters["cpu.idle"] = ticks.idle
                counters["cpu.nice"] = ticks.nice
            }
            CounterSamples.record(counters, at: now)
        }

        var branches: [(String, DataValue)] = []
        if wants("date") { branches.append(("date", dateBranch(now))) }
        if wants("battery") { branches.append(("battery", batteryBranch())) }
        if wants("disk") { branches.append(("disk", diskBranch())) }
        if wants("cpu") { branches.append(("cpu", cpuBranch(ticks, now: now, previous: previous))) }
        if wants("memory") { branches.append(("memory", memoryBranch())) }
        if wants("network") {
            branches.append(("network", networkBranch(traffic, now: now, previous: previous)))
        }
        if wants("system") { branches.append(("system", hostBranch(now))) }
        if wants("devices") { branches.append(("devices", devicesBranch())) }
        if wants("place") { branches.append(("place", placeBranch())) }
        return .ordered(branches)
    }

    /// The shape of the tree with no real values in it, for the editor's
    /// browser before anything has been fetched.
    static var schemaDescription: [(path: String, label: String)] {
        [
            ("date.now", "Current date and time"),
            ("date.epoch", "Seconds since 1970"),
            ("battery.percent", "Charge, 0…1"),
            ("battery.isCharging", "Plugged in and charging"),
            ("battery.isPresent", "This Mac has a battery"),
            ("battery.minutesRemaining", "Estimate, −1 while calculating"),
            ("disk.free", "Free bytes on the boot volume"),
            ("disk.total", "Total bytes"),
            ("disk.used", "Used bytes"),
            ("disk.freeFraction", "Free space, 0…1"),
            ("disk.usedFraction", "Used space, 0…1"),
            ("cpu.usage", "Busy fraction since the last reload, 0…1"),
            ("cpu.user", "User time, 0…1"),
            ("cpu.system", "System time, 0…1"),
            ("cpu.cores", "Number of cores"),
            ("memory.used", "Bytes in use"),
            ("memory.total", "Installed bytes"),
            ("memory.usedFraction", "Memory in use, 0…1"),
            ("memory.compressed", "Compressed bytes"),
            ("network.inPerSecond", "Bytes received per second"),
            ("network.outPerSecond", "Bytes sent per second"),
            ("network.totalIn", "Bytes received since boot"),
            ("network.totalOut", "Bytes sent since boot"),
            ("system.uptime", "Seconds since boot"),
            ("system.bootedAt", "When this Mac started"),
            ("system.thermal", "nominal, fair, serious or critical"),
            ("system.lowPowerMode", "Low Power Mode is on"),
            ("system.name", "This Mac's name"),
            ("system.osVersion", "macOS version"),
            ("devices", "Bluetooth input devices, a list"),
            ("devices[0].name", "First device's name"),
            ("devices[0].percent", "First device's charge, 0…1"),
            ("place.city", "Town or city, once located"),
            ("place.region", "State or province"),
            ("place.country", "Country"),
            ("place.countryCode", "Two-letter country code"),
            ("place.label", "Best available name for where you are"),
            ("place.latitude", "Degrees north"),
            ("place.longitude", "Degrees east"),
            ("place.timeZone", "IANA time zone identifier"),
            ("place.isAuthorised", "Fathom has location permission"),
            ("place.ageMinutes", "How long ago the location was resolved"),
        ]
    }

    // MARK: - Branches added with the wider system scopes

    /// CPU is a rate, not a level: the kernel reports cumulative ticks, so the
    /// number only means anything relative to the previous reload. Before a
    /// second sample exists every field is null and a bound element shows its
    /// fallback, which is honest — there genuinely is no answer yet.
    private static func cpuBranch(_ ticks: (user: Double, system: Double, idle: Double, nice: Double)?,
                                  now: Date,
                                  previous: CounterSamples.Sample?) -> DataValue {
        let cores = Double(ProcessInfo.processInfo.processorCount)
        guard let ticks, let sample = previous,
              let user = sample.values["cpu.user"],
              let system = sample.values["cpu.system"],
              let idle = sample.values["cpu.idle"],
              let nice = sample.values["cpu.nice"]
        else {
            return .ordered([
                ("usage", .null), ("user", .null), ("system", .null),
                ("idle", .null), ("cores", .number(cores)),
            ])
        }

        let dUser = ticks.user - user, dSystem = ticks.system - system
        let dIdle = ticks.idle - idle, dNice = ticks.nice - nice
        let total = dUser + dSystem + dIdle + dNice
        guard total > 0 else {
            return .ordered([
                ("usage", .null), ("user", .null), ("system", .null),
                ("idle", .null), ("cores", .number(cores)),
            ])
        }
        return .ordered([
            ("usage", .number((dUser + dSystem + dNice) / total)),
            ("user", .number(dUser / total)),
            ("system", .number(dSystem / total)),
            ("idle", .number(dIdle / total)),
            ("cores", .number(cores)),
        ])
    }

    private static func memoryBranch() -> DataValue {
        guard let memory = HostMetrics.memory() else {
            return .ordered([("used", .null), ("total", .null), ("free", .null),
                             ("compressed", .null), ("wired", .null), ("usedFraction", .null)])
        }
        return .ordered([
            ("used", .number(memory.used)),
            ("total", .number(memory.total)),
            ("free", .number(memory.free)),
            ("compressed", .number(memory.compressed)),
            ("wired", .number(memory.wired)),
            ("usedFraction", .number(memory.usedFraction)),
        ])
    }

    private static func networkBranch(_ traffic: (received: Double, sent: Double),
                                      now: Date,
                                      previous: CounterSamples.Sample?) -> DataValue {
        let inRate = CounterSamples.rate("net.in", now: traffic.received, at: now, previous: previous)
        let outRate = CounterSamples.rate("net.out", now: traffic.sent, at: now, previous: previous)
        return .ordered([
            ("inPerSecond", inRate.map { .number($0) } ?? .null),
            ("outPerSecond", outRate.map { .number($0) } ?? .null),
            ("totalIn", .number(traffic.received)),
            ("totalOut", .number(traffic.sent)),
        ])
    }

    private static func hostBranch(_ now: Date) -> DataValue {
        let info = ProcessInfo.processInfo
        let booted = HostMetrics.bootedAt()
        let thermal: String = switch info.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        return .ordered([
            ("uptime", booted.map { .number(now.timeIntervalSince($0)) } ?? .null),
            ("bootedAt", booted.map { .date($0) } ?? .null),
            ("thermal", .string(thermal)),
            ("lowPowerMode", .bool(info.isLowPowerModeEnabled)),
            ("name", .string(Host.current().localizedName ?? info.hostName)),
            ("osVersion", .string(info.operatingSystemVersionString)),
        ])
    }

    /// A list rather than named fields, so a repeater can draw one row per
    /// device without the document knowing how many there are.
    /// Where the Mac is, as last written by the app.
    ///
    /// Never resolved here: this runs inside the widget extension as often as
    /// not, and the extension is a reader. `Place` explains the split.
    private static func placeBranch() -> DataValue {
        let place = PlaceStore.current
        return .ordered([
            ("city", place.city.map(DataValue.string) ?? .null),
            ("region", place.region.map(DataValue.string) ?? .null),
            ("country", place.country.map(DataValue.string) ?? .null),
            ("countryCode", place.countryCode.map(DataValue.string) ?? .null),
            ("label", .string(place.label)),
            ("latitude", .number(place.latitude)),
            ("longitude", .number(place.longitude)),
            ("timeZone", place.timeZone.map(DataValue.string) ?? .null),
            ("isAuthorised", .bool(place.isAuthorised)),
            ("ageMinutes", place.isAuthorised ? .number(place.age / 60) : .null),
        ])
    }

    private static func devicesBranch() -> DataValue {
        .array(HostMetrics.bluetoothDevices().map { device in
            .ordered([("name", .string(device.name)), ("percent", .number(device.percent))])
        })
    }

    private static func dateBranch(_ now: Date) -> DataValue {
        .ordered([
            ("now", .date(now)),
            ("epoch", .number(now.timeIntervalSince1970)),
        ])
    }

    private static func batteryBranch() -> DataValue {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let info = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            // Desktop Macs have no battery. Reporting absence explicitly beats
            // reporting 0 %, which would render as a flat empty arc and look
            // like a bug rather than a Mac mini.
            return .ordered([
                ("isPresent", .bool(false)),
                ("percent", .null),
                ("isCharging", .bool(false)),
                ("minutesRemaining", .number(-1)),
            ])
        }

        let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = info[kIOPSIsChargingKey] as? Bool ?? false
        let toEmpty = info[kIOPSTimeToEmptyKey] as? Int ?? -1
        let toFull = info[kIOPSTimeToFullChargeKey] as? Int ?? -1

        return .ordered([
            ("isPresent", .bool(true)),
            ("percent", .number(max > 0 ? Double(current) / Double(max) : 0)),
            ("isCharging", .bool(charging)),
            ("minutesRemaining", .number(Double(charging ? toFull : toEmpty))),
        ])
    }

    private static func diskBranch() -> DataValue {
        // A sandboxed extension's home directory is its own container, but the
        // container lives on the boot volume, so volume-level capacity is the
        // same number the user sees in About This Mac. That is the one piece
        // piece of the sandbox's behaviour that works in our favour.
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey,
                                         .volumeTotalCapacityKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage
        else {
            return .ordered([("free", .null), ("total", .null), ("used", .null),
                             ("freeFraction", .null), ("usedFraction", .null)])
        }

        let freeBytes = Double(free)
        let totalBytes = Double(total)
        let usedBytes = Swift.max(totalBytes - freeBytes, 0)
        return .ordered([
            ("free", .number(freeBytes)),
            ("total", .number(totalBytes)),
            ("used", .number(usedBytes)),
            ("freeFraction", .number(totalBytes > 0 ? freeBytes / totalBytes : 0)),
            ("usedFraction", .number(totalBytes > 0 ? usedBytes / totalBytes : 0)),
        ])
    }
}
