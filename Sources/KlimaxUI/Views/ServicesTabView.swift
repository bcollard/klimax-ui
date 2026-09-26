import SwiftUI

struct ServicesTabView: View {
    @Bindable var model: AppModel
    let cluster: KindCluster
    let services: [KubeService]
    let bridgeCIDR: String?

    private var loadBalancers: [KubeService] {
        services.filter { $0.isLoadBalancer }
    }

    private var probes: [String: AppModel.ProbeResult] {
        model.serviceProbes[cluster.name] ?? [:]
    }

    var body: some View {
        if loadBalancers.isEmpty {
            ContentUnavailableView {
                Label("No LoadBalancer services", systemImage: "network")
            } description: {
                Text("Expose a workload with `type: LoadBalancer` and MetalLB will assign it an IP from the kind bridge CIDR.")
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach(loadBalancers) { svc in
                    ServiceCard(
                        service: svc,
                        probes: probes,
                        dns: dnsContext(for: svc),
                        routable: { model.isRoutable($0) }
                    )
                }
            }
        }
    }

    /// nil when the zone is off or klimax predates it — the card then renders
    /// exactly as before, IP links only.
    private func dnsContext(for svc: KubeService) -> ServiceDNS? {
        guard let zone = model.dnsZone(for: cluster.name) else { return nil }
        let names = model.dnsNames(for: svc, in: cluster.name)
        return ServiceDNS(
            zone: zone,
            server: model.localDNS?.server,
            names: names,
            fleetNames: Set(names.map(\.name).filter { model.isFleetName($0, in: cluster.name) }),
            coverage: Dictionary(uniqueKeysWithValues: names.compactMap { rec in
                model.wildcardCoverage(for: rec.name, in: cluster.name).map { (rec.name, $0) }
            }),
            caEnabled: model.localCA?.enabled == true,
            resolutions: model.nameResolutions[cluster.name] ?? [:],
            externalDNS: model.clusterDetail?.cluster.name == cluster.name
                ? model.clusterDetail?.externalDNS : nil
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("LoadBalancer services")
                .font(.headline)
            Text("\(loadBalancers.count) total")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let cidr = bridgeCIDR {
                Text("kind bridge \(cidr)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// What the local DNS zone knows about one Service.
private struct ServiceDNS {
    let zone: String
    let server: String?
    /// Automatic name first, then annotation / Ingress names on the same VIP.
    let names: [LocalDNSRecord]
    /// Names under the fleet zone rather than the cluster's.
    let fleetNames: Set<String>
    /// Names a klimax wildcard covers.
    let coverage: [String: WildcardCoverage]
    /// Whether the local CA is on — decides whether "no wildcard" is worth saying.
    let caEnabled: Bool
    let resolutions: [String: NameResolution]
    let externalDNS: ExternalDNSState?

    /// The name links use: the automatic one when published.
    var primaryName: String? { names.first?.name }
}

private struct ServiceCard: View {
    let service: KubeService
    let probes: [String: AppModel.ProbeResult]
    let dns: ServiceDNS?
    let routable: (String) -> Bool?

    private var ips: [String] { service.externalIPs }
    private var ports: [KubeService.Port] { service.spec.ports ?? [] }
    private var unroutedIPs: [String] { ips.filter { routable($0) == false } }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(service.metadata.name).font(.headline)
                            Text(service.metadata.namespace ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                        }
                        if ips.isEmpty {
                            Text("Pending external IP…")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !unroutedIPs.isEmpty {
                            Label("\(unroutedIPs.joined(separator: ", ")) is outside the kind bridge CIDR — the Mac has no route to it",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                }

                if let dns, !ips.isEmpty {
                    Divider()
                    dnsNamesBlock(dns)
                }

                if !ips.isEmpty, !ports.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ips, id: \.self) { ip in
                            ForEach(ports) { port in
                                EndpointRow(
                                    ip: ip,
                                    host: dns?.names.first { $0.ip == ip }?.name,
                                    port: port,
                                    probe: probes["\(ip):\(port.port)"]
                                )
                            }
                        }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ServiceCard {
    @ViewBuilder
    fileprivate func dnsNamesBlock(_ dns: ServiceDNS) -> some View {
        if dns.names.isEmpty {
            Label(emptyNamesText(dns), systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(dns.names) { rec in
                    DNSNameRow(
                        record: rec,
                        resolution: dns.resolutions[rec.name],
                        server: dns.server,
                        isFleet: dns.fleetNames.contains(rec.name),
                        coverage: dns.coverage[rec.name],
                        caEnabled: dns.caEnabled
                    )
                }
            }
        }
    }

    private func emptyNamesText(_ dns: ServiceDNS) -> String {
        switch dns.externalDNS {
        case .missing:
            return "No DNS name: this cluster isn't attached to local DNS. Attach it from the Info tab."
        case .notReady:
            return "No DNS name yet: ExternalDNS isn't ready in this cluster."
        default:
            return "No DNS name yet. ExternalDNS publishes new Services within ~15 s — press ⌘R to re-check."
        }
    }
}

/// One published name, with whether macOS resolves it to the VIP.
private struct DNSNameRow: View {
    let record: LocalDNSRecord
    let resolution: NameResolution?
    let server: String?
    let isFleet: Bool
    let coverage: WildcardCoverage?
    let caEnabled: Bool
    @State private var copied: String?

    private var digCommand: String {
        server.map { "dig @\($0) \(record.name) +short" } ?? "dscacheutil -q host -a name \(record.name)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            resolutionDot.frame(width: 12)
            Text("DNS")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)
            Text(verbatim: record.name)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "→ \(record.ip)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            if isFleet {
                Text("fleet")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color.accentColor)
                    .help("Fleet-wide name: published under the fleet zone by this cluster's ExternalDNS. The first member to publish a name owns it.")
            }
            if let coverage {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("Covered by the klimax wildcard \(coverage.wildcard) (Secret \(coverage.secret)), trusted by this Mac through the klimax root CA.")
            } else if caEnabled {
                Image(systemName: "lock.slash")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help(Self.noWildcardHelp)
            }
            Spacer()
            copyButton(record.name, systemImage: "doc.on.doc", help: "Copy \(record.name)")
            copyButton(digCommand, systemImage: "terminal",
                       help: "Copy `\(digCommand)`. dig skips /etc/resolver, so a bare `dig \(record.name)` fails even when browsers and curl resolve it; use `dscacheutil -q host -a name \(record.name)` to test the Mac's own path.")
        }
    }

    static let noWildcardHelp = "No klimax wildcard covers this name. A wildcard covers one label, so <svc>.<ns>.<cluster>.<domain> isn't covered: use a one-label hostname annotation (app.<cluster>.<domain>), a cert-manager Certificate from the klimax-ca ClusterIssuer, or issue the cluster's wildcard from the Info tab."

    private func copyButton(_ text: String, systemImage: String, help: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
            Task {
                try? await Task.sleep(for: .seconds(2))
                if copied == text { copied = nil }
            }
        } label: {
            Image(systemName: copied == text ? "checkmark" : systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder
    private var resolutionDot: some View {
        if let resolution {
            let (color, text) = verdict(resolution)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .help(text)
        } else {
            ProgressView()
                .controlSize(.mini)
                .help("Resolving…")
        }
    }

    private func verdict(_ r: NameResolution) -> (Color, String) {
        if r.addresses.contains(record.ip) {
            return (.green, "Resolves on this Mac to \(record.ip)")
        }
        if r.addresses.isEmpty {
            return (.red, "Does not resolve on this Mac. klimax publishes it, so check /etc/resolver and the DNS server under Settings › Diagnostics. macOS caches a failed lookup for ~75 s, so a name queried before it was published can take that long to appear.")
        }
        return (.orange, "Resolves to \(r.addresses.joined(separator: ", ")), not \(record.ip) — a stale cached answer, or another resolver claims the domain")
    }
}

private struct EndpointRow: View {
    let ip: String
    /// Published DNS name for this VIP, used for the link when present.
    let host: String?
    let port: KubeService.Port
    let probe: AppModel.ProbeResult?

    private var isTCP: Bool { port.protocolValue.uppercased() == "TCP" }
    private var endpoint: String { "\(host ?? ip):\(port.port)" }

    private var url: URL? {
        let scheme = scheme(for: port)
        let portSuffix = (scheme == "http" && port.port == 80) || (scheme == "https" && port.port == 443)
            ? ""
            : ":\(port.port)"
        return URL(string: "\(scheme)://\(host ?? ip)\(portSuffix)")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            probeDot
                .frame(width: 12)
            Text(port.protocolValue.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .leading)
            if let url, isTCP {
                Link(url.absoluteString, destination: url)
                    .font(.system(.callout, design: .monospaced))
            } else {
                Text(verbatim: endpoint)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            if host != nil {
                Text(verbatim: ip)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if let name = port.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let target = port.targetPortString {
                Text(verbatim: "→ \(target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(endpoint, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(endpoint)")
        }
    }

    @ViewBuilder
    private var probeDot: some View {
        if !isTCP {
            Image(systemName: "minus.circle")
                .foregroundStyle(.tertiary)
                .font(.caption)
                .help("TCP probe not applicable for \(port.protocolValue) port")
        } else if let probe {
            Circle()
                .fill(probe.isOpen ? Color.green : Color.red)
                .frame(width: 8, height: 8)
                .help(probeTooltip(probe))
        } else {
            ProgressView()
                .controlSize(.mini)
                .help("Probing…")
        }
    }

    private func probeTooltip(_ p: AppModel.ProbeResult) -> String {
        let ago = Self.relativeFormatter.localizedString(for: p.timestamp, relativeTo: Date())
        return p.isOpen
            ? "TCP \(ip):\(port.port) — reachable (\(ago))"
            : "TCP \(ip):\(port.port) — unreachable (\(ago))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func scheme(for port: KubeService.Port) -> String {
        switch port.port {
        case 443, 8443: return "https"
        default: return "http"
        }
    }
}
