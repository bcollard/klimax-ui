import Foundation

/// Where an action-log entry belongs, so each view surfaces only the logs
/// relevant to what it shows. The aggregated console panel ignores scope and
/// shows everything.
enum LogScope: Hashable, Sendable {
    /// VM lifecycle (start/stop) — shown on the overview / VM home.
    case vm
    /// A specific cluster's lifecycle (delete, label, context switch, create) —
    /// shown on that cluster's Info/Services tabs.
    case cluster(String)
    /// metrics-server install/uninstall for a cluster — shown on its Metrics tab.
    case metrics(String)
    /// A guest-VM container's lifecycle (start/stop/restart) — shown on that
    /// container's detail view.
    case container(String)
    /// A whole compose stack's lifecycle (start all / stop all), keyed by
    /// project name — shown next to the stack's group header.
    case composeStack(String)
    /// A whole fleet's lifecycle (delete), keyed by fleet name — shown on the
    /// overview, since the fleet's clusters (and so its header) are gone after.
    case fleet(String)
    /// Fleet-wide actions with no single home (e.g. delete-all) — shown on the overview.
    case general

    /// Whether the overview's "Last action" card surfaces this scope.
    var showsOnOverview: Bool {
        switch self {
        case .vm, .fleet, .general: true
        default: false
        }
    }
}

/// One completed action's log, with the scope that decides where it surfaces.
struct LogRecord: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let scope: LogScope
    let label: String
    let text: String
}
