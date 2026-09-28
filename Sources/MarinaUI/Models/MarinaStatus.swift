import Foundation

/// Decoded `marina status -o json`. Only the parts the UI can't already read
/// more cheaply from the filesystem are modelled — chiefly the mount list,
/// which marina reads from the **Lima instance config** rather than from
/// `~/.marina/config.yaml`. That distinction is the whole point: the instance
/// is what the VM actually has, the config file is what it will have after the
/// next restart, and `pendingRestart` is marina telling us they disagree.
struct MarinaStatus: Sendable, Hashable, Decodable {
    let mounts: Mounts?
    /// Local DNS zone for LoadBalancer Services (marina 0.2.0+). Absent on
    /// older marina, which the UI treats as "unknown" and hides every DNS
    /// feature rather than claiming the zone is off.
    let dns: DNS?

    struct DNS: Sendable, Hashable, Decodable {
        let enabled: Bool
        /// e.g. `demo.internal`; names are `<svc>.<ns>.<cluster>.<domain>`.
        let domain: String?
        /// CoreDNS address on the kind network (`x.y.255.53`).
        let server: String?
        /// Whether `/etc/resolver/<domain>` on the Mac matches what marina writes.
        let hostResolver: Bool
        /// nil when the VM isn't running — marina can't ask docker then.
        let serverRunning: Bool?
        /// Local CA for the zone (marina 0.2.2+); nil when `network.dns.tls` is
        /// off or marina predates it.
        let tls: TLS?

        struct TLS: Sendable, Hashable, Decodable {
            /// `~/.marina/pki/<domain>/root.crt`, once the root exists.
            let root: String?
            let exists: Bool
            /// Trusted in the macOS System keychain — without it browsers reject
            /// every certificate under the zone.
            let trusted: Bool
        }

        /// The subzone a cluster's ExternalDNS publishes into.
        func zone(for cluster: String) -> String? {
            guard enabled, let domain, !domain.isEmpty else { return nil }
            return "\(cluster).\(domain)"
        }
    }

    struct Mounts: Sendable, Hashable, Decodable {
        let shares: [Share]
        let pendingRestart: Bool
        let error: String?

        struct Share: Sendable, Hashable, Decodable, Identifiable {
            let hostPath: String
            let guestPath: String
            let writable: Bool

            var id: String { "\(hostPath)→\(guestPath)" }

            /// marina shares its own registry cache; that one is plumbing, not
            /// something the user asked for, so it's labelled rather than
            /// listed as if they had configured it.
            var isMarinaInternal: Bool {
                hostPath.contains("/.marina/")
            }
        }
    }
}

/// One host directory the guest can see, with the guest path a container bind
/// would have to fall under to actually reach the Mac.
extension MarinaStatus.Mounts {
    /// The share backing a container bind source, if any.
    ///
    /// A bind resolves to real host data only when its source is inside a
    /// shared guest path. Anything else is silently created empty by dockerd in
    /// the guest — the container starts fine and sees nothing, which is the
    /// failure `vm.mounts` exists to prevent.
    func share(backing guestSource: String) -> Share? {
        shares.first { share in
            guestSource == share.guestPath
                || guestSource.hasPrefix(share.guestPath.hasSuffix("/")
                                         ? share.guestPath
                                         : share.guestPath + "/")
        }
    }
}
