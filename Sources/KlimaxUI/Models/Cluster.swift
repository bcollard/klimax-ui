import Foundation

struct KindCluster: Identifiable, Hashable, Sendable, Decodable {
    var id: String { name }
    let name: String
    let num: Int
    let apiPort: Int
    let kubeconfigPath: String
}
