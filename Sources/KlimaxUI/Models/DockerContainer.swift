import Foundation

/// One container from `docker ps -a` inside the klimax guest VM.
struct DockerContainer: Sendable, Hashable, Identifiable {
    /// Full 64-char container ID (we ask docker for `--no-trunc`).
    let id: String
    let name: String
    let image: String
    /// `running`, `exited`, `created`, `paused`, `restarting`, `dead`…
    let state: String
    /// Human-readable status line, e.g. "Up 2 days" / "Exited (0) 3 hours ago".
    let status: String
    let ports: [PortMapping]
    let createdAt: Date?
    let command: String
    let networks: [String]
    let mounts: [String]

    /// The kind cluster this container is a node of, and its role. kind stamps
    /// every node container with these, which is how `kind get clusters` itself
    /// discovers clusters — the authoritative signal, not the container name.
    let kindCluster: String?
    let kindRole: String?

    /// Compose stack membership, when this container was started by
    /// `docker compose`.
    let compose: ComposeMembership?

    /// Label map, for display.
    ///
    /// Normally exact, re-read as JSON from `docker inspect`. It falls back to
    /// parsing `docker ps --format '{{.Labels}}'`, which comma-joins labels
    /// **without escaping commas inside values** — so a value containing one
    /// (`com.docker.compose.project.config_files` with several `-f` files,
    /// `com.docker.compose.depends_on`) splits into a bogus entry. Nothing keys
    /// behavior off this map either way; every label the app reasons about is
    /// read from its own `{{.Label "…"}}` column.
    let labels: [String: String]

    /// Same container with an exact label map swapped in.
    func withLabels(_ labels: [String: String]) -> DockerContainer {
        DockerContainer(
            id: id, name: name, image: image, state: state, status: status,
            ports: ports, createdAt: createdAt, command: command,
            networks: networks, mounts: mounts,
            kindCluster: kindCluster, kindRole: kindRole, compose: compose,
            labels: labels
        )
    }

    var shortID: String { String(id.prefix(12)) }
    var isRunning: Bool { state == "running" }

    /// Membership in a `docker compose` project. Compose stamps these on every
    /// container it starts; `project` is the stack name (the directory name
    /// unless overridden by `-p` / `COMPOSE_PROJECT_NAME`).
    struct ComposeMembership: Sendable, Hashable {
        let project: String
        let service: String?
        /// Replica index within the service, 1-based.
        let containerNumber: Int?
        /// `docker compose run` throwaway rather than a `up` service container.
        let isOneOff: Bool
        let workingDir: String?
        /// The compose file(s) the stack was built from — several when the user
        /// passed repeated `-f` flags.
        let configFiles: [String]

        /// "web #2", or just the service, for a compact row subtitle.
        var serviceLabel: String? {
            guard let service else { return nil }
            guard let n = containerNumber, n > 1 else { return service }
            return "\(service) #\(n)"
        }
    }

    /// Why klimax owns this container, or nil when it's the user's own.
    enum Managed: Sendable, Hashable {
        case kindNode(cluster: String, role: String?)
        case registryMirror(name: String)
    }

    /// Classify against the mirrors declared in the klimax config.
    ///
    /// kind nodes are identified by label. Mirrors carry no klimax label at all,
    /// so the config's mirror names are the primary signal; the `registry-` +
    /// `registry:<tag>` shape is a fallback for a config that has drifted from
    /// what is actually running (a mirror removed from the file but still up).
    func managed(mirrorNames: Set<String>) -> Managed? {
        if let kindCluster {
            return .kindNode(cluster: kindCluster, role: kindRole)
        }
        if mirrorNames.contains(name) {
            return .registryMirror(name: name)
        }
        if name.hasPrefix("registry-"),
           image == "registry" || image.hasPrefix("registry:") {
            return .registryMirror(name: name)
        }
        return nil
    }

    /// One entry of docker's port column: `0.0.0.0:5050->5050/tcp` (published)
    /// or `5000/tcp` (exposed only).
    struct PortMapping: Sendable, Hashable, Identifiable {
        let hostIP: String?
        let hostPort: Int?
        let containerPort: Int
        let proto: String

        var id: String { "\(hostIP ?? "-"):\(hostPort ?? 0)->\(containerPort)/\(proto)" }
        var isPublished: Bool { hostPort != nil }

        var display: String {
            if let hostPort {
                return "\(hostIP.map { "\($0):" } ?? "")\(hostPort) → \(containerPort)/\(proto)"
            }
            return "\(containerPort)/\(proto)"
        }
    }
}

/// Un-managed containers bucketed for display: one entry per compose project,
/// then the containers that belong to no stack.
struct ContainerGroup: Identifiable, Sendable, Hashable {
    /// Compose project name, or nil for the standalone bucket.
    let project: String?
    let containers: [DockerContainer]

    var id: String { project ?? "\u{0}standalone" }
    var title: String { project ?? "Standalone" }
    var isStandalone: Bool { project == nil }

    /// Compose records the directory the stack was launched from; all members
    /// of a project agree on it.
    var workingDir: String? {
        containers.compactMap { $0.compose?.workingDir }.first
    }

    var runningCount: Int { containers.filter(\.isRunning).count }
}
