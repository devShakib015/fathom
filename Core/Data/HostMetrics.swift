import Foundation
import Darwin
import IOKit

/// The numbers macOS knows about itself, read straight from the kernel.
///
/// All of this is available to a sandboxed process without any additional
/// entitlement and without asking the user for anything, which is why it lives
/// in the plain system source rather than behind a permission.
enum HostMetrics {

    // MARK: - CPU

    /// Cumulative CPU ticks since boot. A rate needs two of these.
    static func cpuTicks() -> (user: Double, system: Double, idle: Double, nice: Double)? {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (Double(info.cpu_ticks.0), Double(info.cpu_ticks.1),
                Double(info.cpu_ticks.2), Double(info.cpu_ticks.3))
    }

    // MARK: - Memory

    struct Memory {
        var total: Double
        var used: Double
        var free: Double
        var compressed: Double
        var wired: Double
        var usedFraction: Double
    }

    static func memory() -> Memory? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let page = Double(vm_kernel_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let free = Double(stats.free_count) * page
        let wired = Double(stats.wire_count) * page
        let compressed = Double(stats.compressor_page_count) * page
        // Apple's own "memory used" is active + wired + compressed, which is
        // what Activity Monitor shows. Inactive pages are counted as available
        // because the system will reclaim them without anybody noticing.
        let used = (Double(stats.active_count) * page) + wired + compressed

        return Memory(total: total, used: used, free: max(total - used, 0),
                      compressed: compressed, wired: wired,
                      usedFraction: total > 0 ? min(used / total, 1) : 0)
    }

    // MARK: - Uptime

    static func bootedAt() -> Date? {
        var timeval = timeval()
        var size = MemoryLayout<Darwin.timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &timeval, &size, nil, 0) == 0, timeval.tv_sec != 0 else { return nil }
        return Date(timeIntervalSince1970: Double(timeval.tv_sec))
    }

    // MARK: - Network

    /// Cumulative bytes across every physical interface. Loopback is excluded,
    /// otherwise local traffic inflates the number into nonsense.
    static func networkBytes() -> (received: Double, sent: Double) {
        var received: Double = 0
        var sent: Double = 0
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let name = current.pointee.ifa_name.map({ String(cString: $0) }),
                  !name.hasPrefix("lo"),
                  current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  let data = current.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            received += Double(data.pointee.ifi_ibytes)
            sent += Double(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }

    // MARK: - Bluetooth input devices

    /// Battery levels for Magic Mouse, Trackpad and Keyboard.
    ///
    /// These arrive through the HID event service, which does not cover AirPods
    /// — those report through a different path that is not public, and
    /// promising them would be a feature claim that quietly fails.
    static func bluetoothDevices() -> [(name: String, percent: Double)] {
        var found: [(String, Double)] = []
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let percent = IORegistryEntryCreateCFProperty(
                    service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Int else { continue }
            let name = (IORegistryEntryCreateCFProperty(
                service, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String) ?? "Device"
            found.append((name, Double(percent) / 100))
        }
        return found.sorted { $0.0 < $1.0 }
    }
}
