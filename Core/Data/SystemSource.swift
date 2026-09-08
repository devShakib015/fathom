import Foundation
import IOKit.ps

/// The values macOS already knows, offered as a data source so that a widget
/// bound to the clock and a widget bound to a weather endpoint are built the
/// same way. There is no separate "clock element".
///
/// Read fresh on every timeline reload. The extension is usually a brand new
/// process by then, so there is nothing to cache and nothing to invalidate.
enum SystemSource {

    static func snapshot(now: Date = Date()) -> DataValue {
        .ordered([
            ("date", dateBranch(now)),
            ("battery", batteryBranch()),
            ("disk", diskBranch()),
        ])
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
        ]
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
        // of trap 3 that works in our favour.
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
