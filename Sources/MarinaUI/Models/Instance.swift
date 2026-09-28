import Foundation

struct Instance: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let dir: URL
    let runtime: Runtime
    let ssh: SSHEndpoint?
    let lima: LimaConfig?

    enum Runtime: Sendable, Hashable {
        case running(vzPID: Int32, haPID: Int32?)
        case stopped
        case unknown
    }

    struct LimaConfig: Sendable, Hashable {
        let cpus: Int?
        let memory: String?
        let disk: String?
        let vmType: String?
    }

    var isRunning: Bool {
        if case .running = runtime { return true }
        return false
    }
}

struct SSHEndpoint: Sendable, Hashable {
    let hostAlias: String
    let configPath: String
    let hostname: String
    let port: Int
    let user: String
    let identityFile: String
    let controlPath: String?
}
