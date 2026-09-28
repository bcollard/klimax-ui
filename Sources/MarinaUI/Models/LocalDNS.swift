import Foundation

/// One A record from `marina dns list -o json`. TXT ownership records are
/// already filtered out by marina.
struct LocalDNSRecord: Sendable, Hashable, Decodable, Identifiable {
    let name: String
    let ip: String

    var id: String { "\(name)→\(ip)" }
}

/// Why a name points at a Service's VIP.
enum DNSNameSource: Sendable, Hashable {
    /// The Service's `external-dns.kubernetes.io/hostname` annotation.
    case annotation
    /// `network.dns.nameTemplate` under the cluster zone.
    case automatic
    /// Published by something else on the same VIP — an Ingress host on an
    /// ingress controller's Service, typically.
    case sharedVIP
}

/// Decoded `marina ca status -o json` (marina 0.2.2+). Host-side only — it
/// reads `~/.marina/pki` — so it answers with the VM stopped.
struct LocalCAStatus: Sendable, Hashable, Decodable {
    let enabled: Bool
    let domain: String
    let root: String?
    let exists: Bool
    let trusted: Bool
    /// Root expiry, `YYYY-MM-DD`.
    let notAfter: String?
    /// Clusters with an issued wildcard.
    let clusters: [Zone]
    /// Fleets with an issued wildcard (marina 0.2.3+).
    let fleets: [Zone]?

    struct Zone: Sendable, Hashable, Decodable {
        let name: String
        /// `*.<name>.<domain>`.
        let wildcard: String
        let notAfter: String?
    }

    func cluster(_ name: String) -> Zone? { clusters.first { $0.name == name } }
    func fleet(_ name: String) -> Zone? { fleets?.first { $0.name == name } }
}

/// Which marina wildcard certificate covers a name, if any. A wildcard covers
/// exactly one label, so the default two-label automatic name
/// (`<svc>.<ns>.<cluster>.<domain>`) is **not** covered.
enum WildcardCoverage: Sendable, Hashable {
    /// `*.<cluster>.<domain>`, Secret `default/marina-wildcard-tls`.
    case cluster(wildcard: String)
    /// `*.<fleet>.<domain>`, Secret `default/marina-fleet-wildcard-tls`.
    case fleet(wildcard: String)

    var wildcard: String {
        switch self {
        case .cluster(let w), .fleet(let w): return w
        }
    }

    var secret: String {
        switch self {
        case .cluster: return "default/marina-wildcard-tls"
        case .fleet: return "default/marina-fleet-wildcard-tls"
        }
    }

    /// Whether `name` is exactly one label under `zone`.
    static func isOneLabel(_ name: String, under zone: String) -> Bool {
        guard name.hasSuffix("." + zone) else { return false }
        let label = name.dropLast(zone.count + 1)
        return !label.isEmpty && !label.contains(".")
    }
}

/// How a published name resolves on the Mac, through `/etc/resolver` — the
/// same path a browser or `curl` takes, unlike `dig`.
struct NameResolution: Sendable, Hashable {
    let timestamp: Date
    /// IPv4 addresses macOS returned; empty for NXDOMAIN or a timeout.
    let addresses: [String]
}

/// Whether a cluster's ExternalDNS is installed, from its deployment in the
/// `external-dns` namespace.
enum ExternalDNSState: Sendable, Hashable {
    case ready
    case notReady
    /// Created before `network.dns` was on (or the install failed):
    /// `marina dns attach` is the fix.
    case missing
}

/// IPv4 CIDR membership, for telling whether a published address sits on the
/// kind bridge the Mac has a route to.
struct IPv4CIDR: Sendable, Hashable {
    let network: UInt32
    let mask: UInt32

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let bits = Int(parts[1]), (0...32).contains(bits),
              let base = Self.parse(String(parts[0]))
        else { return nil }
        mask = bits == 0 ? 0 : UInt32.max << UInt32(32 - bits)
        network = base & mask
    }

    func contains(_ ip: String) -> Bool {
        guard let addr = Self.parse(ip) else { return false }
        return addr & mask == network
    }

    static func parse(_ ip: String) -> UInt32? {
        let octets = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return nil }
        var value: UInt32 = 0
        for o in octets {
            guard let n = UInt8(o) else { return nil }
            value = value << 8 | UInt32(n)
        }
        return value
    }
}

/// Resolves a name with `getaddrinfo`, which on macOS goes through
/// mDNSResponder and so honours `/etc/resolver/<domain>`.
enum HostResolver {
    static func resolveIPv4(_ name: String) async -> [String] {
        await Task.detached {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var res: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(name, nil, &hints, &res) == 0, let first = res else { return [] }
            defer { freeaddrinfo(first) }
            var out: [String] = []
            var cur: UnsafeMutablePointer<addrinfo>? = first
            while let ai = cur {
                if let sa = ai.pointee.ai_addr, ai.pointee.ai_family == AF_INET {
                    var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        let s = String(decoding: bytes, as: UTF8.self)
                        if !out.contains(s) { out.append(s) }
                    }
                }
                cur = ai.pointee.ai_next
            }
            return out
        }.value
    }
}
