import Foundation

/// Decoded `klimax status -o json`. Only the parts the UI can't already read
/// more cheaply from the filesystem are modelled — chiefly the mount list,
/// which klimax reads from the **Lima instance config** rather than from
/// `~/.klimax/config.yaml`. That distinction is the whole point: the instance
/// is what the VM actually has, the config file is what it will have after the
/// next restart, and `pendingRestart` is klimax telling us they disagree.
struct KlimaxStatus: Sendable, Hashable, Decodable {
    let mounts: Mounts?

    struct Mounts: Sendable, Hashable, Decodable {
        let shares: [Share]
        let pendingRestart: Bool
        let error: String?

        struct Share: Sendable, Hashable, Decodable, Identifiable {
            let hostPath: String
            let guestPath: String
            let writable: Bool

            var id: String { "\(hostPath)→\(guestPath)" }

            /// klimax shares its own registry cache; that one is plumbing, not
            /// something the user asked for, so it's labelled rather than
            /// listed as if they had configured it.
            var isKlimaxInternal: Bool {
                hostPath.contains("/.klimax/")
            }
        }
    }
}

/// One host directory the guest can see, with the guest path a container bind
/// would have to fall under to actually reach the Mac.
extension KlimaxStatus.Mounts {
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
