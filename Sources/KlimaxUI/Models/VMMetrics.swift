import Foundation

/// One time-stamped reading of VM CPU and memory usage.
struct VMSample: Sendable, Hashable, Identifiable {
    let id: UUID
    let timestamp: Date
    /// CPU usage percentage (0-100). Nil only for the very first sample where
    /// no previous reading exists to compute a delta from.
    let cpuPercent: Double?
    let memUsedMiB: Double
    let memTotalMiB: Double
}

/// Bounded ring buffer of VM samples. Capacity at 5s polling = 5min by default.
struct VMHistory: Sendable {
    private(set) var samples: [VMSample] = []
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    mutating func append(_ sample: VMSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

/// Raw counters captured in a single SSH probe. Used to compute deltas
/// between consecutive samples for CPU percentage.
struct GuestRawSample: Sendable {
    let timestamp: Date
    let cpuTotalTicks: UInt64
    let cpuIdleTicks: UInt64
    let memTotalKB: Int
    let memAvailableKB: Int
    /// Raw `/proc/loadavg` line, so the 5 s poll can also drive the Load row.
    let loadAvg: String?
}
