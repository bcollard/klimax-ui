import Foundation

enum SidebarSelection: Hashable, Sendable {
    case cluster(name: String)
    case mirror(name: String)
}
