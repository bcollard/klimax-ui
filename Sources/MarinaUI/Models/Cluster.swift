import Foundation

struct KindCluster: Identifiable, Hashable, Sendable, Decodable {
    var id: String { name }
    let name: String
    let num: Int
    let apiPort: Int
    let kubeconfigPath: String
}

/// Clusters bucketed for display: one entry per `marina.run/fleet` value, then
/// the clusters that belong to no fleet (or whose labels haven't loaded yet).
struct ClusterGroup: Identifiable, Sendable, Hashable {
    /// Fleet name, or nil for the ungrouped bucket.
    let fleet: String?
    let clusters: [KindCluster]

    var id: String { fleet ?? "\u{0}ungrouped" }
    var isUngrouped: Bool { fleet == nil }
}
