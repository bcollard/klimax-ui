import Foundation

/// A single point-in-time reading for one node.
struct NodeMetric: Sendable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let timestamp: Date
    let cpuMillicores: Double
    let memoryMiB: Double
}

/// A single point-in-time reading for one pod (summed across containers).
struct PodMetric: Sendable, Hashable, Identifiable {
    var id: String { "\(namespace)/\(name)" }
    let name: String
    let namespace: String
    let timestamp: Date
    let cpuMillicores: Double
    let memoryMiB: Double
}

/// One sample of cluster-wide totals captured at one polling tick.
struct ClusterMetricSample: Sendable, Hashable, Identifiable {
    let id = UUID()
    let timestamp: Date
    let totalCPUMillicores: Double
    let totalMemoryMiB: Double
    let perNode: [NodeMetric]
}

/// Bounded ring buffer of cluster samples. Keeps last `capacity` entries.
struct MetricsHistory: Sendable {
    private(set) var samples: [ClusterMetricSample] = []
    let capacity: Int

    init(capacity: Int = 60) {
        self.capacity = capacity
    }

    mutating func append(_ sample: ClusterMetricSample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    mutating func clear() { samples.removeAll() }
}
