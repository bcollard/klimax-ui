import Foundation

enum SidebarSelection: Hashable, Sendable {
    case cluster(name: String)
    case mirror(name: String)
    /// A container in the guest VM that klimax doesn't manage, keyed by its
    /// full docker ID — names are mutable and not guaranteed unique over time.
    case container(id: String)
}
