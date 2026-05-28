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
                    ServiceCard(service: svc, bridgeCIDR: bridgeCIDR, probes: probes)
                }
            }
        }
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
            Button {
                Task { await model.loadClusterDetail(for: cluster) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Re-fetch services and re-probe endpoints")
        }
    }
}

private struct ServiceCard: View {
    let service: KubeService
    let bridgeCIDR: String?
    let probes: [String: AppModel.ProbeResult]

    private var ips: [String] { service.externalIPs }
    private var ports: [KubeService.Port] { service.spec.ports ?? [] }

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
                    }
                    Spacer()
                }

                if !ips.isEmpty, !ports.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(ips, id: \.self) { ip in
                            ForEach(ports) { port in
                                EndpointRow(ip: ip, port: port, probe: probes["\(ip):\(port.port)"])
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

private struct EndpointRow: View {
    let ip: String
    let port: KubeService.Port
    let probe: AppModel.ProbeResult?

    private var isTCP: Bool { port.protocolValue.uppercased() == "TCP" }

    private var url: URL? {
        let scheme = scheme(for: port)
        let portSuffix = (scheme == "http" && port.port == 80) || (scheme == "https" && port.port == 443)
            ? ""
            : ":\(port.port)"
        return URL(string: "\(scheme)://\(ip)\(portSuffix)")
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
                Text("\(ip):\(port.port)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let name = port.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let target = port.targetPortString {
                Text("→ \(target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString("\(ip):\(port.port)", forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy \(ip):\(port.port)")
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
            ? "TCP \(ip):\(port.port) — open (\(ago))"
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
