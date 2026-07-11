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
    /// Fleet-wide actions with no single home (e.g. delete-all) — shown on the overview.
    case general
}

/// One completed action's log, with the scope that decides where it surfaces.
struct LogRecord: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let scope: LogScope
    let label: String
    let text: String
}
