import SwiftUI

struct ClusterDetailView: View {
    @Bindable var model: AppModel
    let cluster: KindCluster
    @State private var tab: Tab = .info

    enum Tab: Hashable { case info, services, metrics }

    private var detail: AppModel.ClusterDetail? {
        if model.clusterDetail?.cluster.name == cluster.name {
            return model.clusterDetail
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                Picker("", selection: $tab) {
                    Text("Info").tag(Tab.info)
                    Text("Services").tag(Tab.services)
                    Text("Metrics").tag(Tab.metrics)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let err = detail?.error {
                        errorBanner(err)
                    }
                    switch tab {
                    case .info:
                        nodesCard
                        podsCard
                        kubeconfigCard
                    case .services:
                        ServicesTabView(
                            model: model,
                            cluster: cluster,
                            services: detail?.services ?? [],
                            bridgeCIDR: model.config?.network?.kindBridgeCIDR
                        )
                    case .metrics:
                        metricsTabBody
                    }
                    if !model.actionLog.isEmpty {
                        LogConsoleView(
                            title: "Last action log",
                            text: model.actionLog,
                            maxHeight: 180
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: cluster.name) {
            await model.loadClusterDetail(for: cluster)
        }
    }

    @ViewBuilder
    private var metricsTabBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            metricsServerCard
            if detail?.metricsServerReady == true {
                MetricsChartsView(model: model, cluster: cluster)
            } else {
                Text("Install metrics-server above to enable live CPU and memory graphs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cluster.name).font(.largeTitle.bold())
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 12) {
                        metaPill("num", "\(cluster.num)")
                        metaPill("api", ":\(cluster.apiPort)")
                        if let v = detail?.serverVersion {
                            metaPill("k8s", v)
                        }
                        if let createdAt = model.clusterCreatedAt[cluster.name] {
                            metaPill("age", RelativeAge.format(since: createdAt, now: context.date))
                        }
                    }
                    .font(.callout)
                }
            }
            Spacer()
            if detail?.loading == true {
                ProgressView().controlSize(.small)
            }
            Button(role: .destructive) {
                Task { await model.deleteCluster(named: cluster.name) }
            } label: {
                Label("Delete cluster", systemImage: "trash")
            }
            .disabled(model.inFlightAction != nil)
        }
    }

    // MARK: - Metrics server

    private var metricsServerCard: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: detail?.metricsServerReady == true
                      ? "chart.line.uptrend.xyaxis.circle.fill"
                      : "chart.line.uptrend.xyaxis.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(detail?.metricsServerReady == true ? .green : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("metrics-server")
                        .font(.headline)
                    Text(metricsStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if detail?.metricsServerReady == true {
                    Button(role: .destructive) {
                        Task { await model.uninstallMetricsServer(for: cluster) }
                    } label: {
                        Label("Uninstall", systemImage: "minus.circle")
                    }
                    .disabled(model.inFlightAction != nil)
                } else {
                    Button {
                        Task { await model.installMetricsServer(for: cluster) }
                    } label: {
                        Label("Install metrics-server", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.inFlightAction != nil)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metricsStatusText: String {
        guard let detail = detail else { return "Loading…" }
        if detail.metricsServerReady {
            return "Installed and ready in kube-system."
        }
        return "Not installed. Required for `kubectl top` and HPA."
    }

    // MARK: - Nodes

    private var nodesCard: some View {
        GroupBox("Nodes") {
            if let nodes = detail?.nodes, !nodes.isEmpty {
                VStack(spacing: 0) {
                    ForEach(nodes) { n in
                        nodeRow(n)
                        if n.id != nodes.last?.id { Divider() }
                    }
                }
                .padding(.vertical, 2)
            } else {
                Text(detail?.loading == true ? "Loading…" : "No nodes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private func nodeRow(_ n: KubeNode) -> some View {
        HStack(alignment: .top) {
            Circle()
                .fill(n.ready ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(n.metadata.name).font(.body.bold())
                HStack(spacing: 10) {
                    if let v = n.status.nodeInfo?.kubeletVersion {
                        Text("kubelet \(v)")
                    }
                    if let arch = n.status.nodeInfo?.architecture {
                        Text(arch)
                    }
                    if let cpu = n.status.capacity?.cpu {
                        Text("cpu \(cpu)")
                    }
                    if let mem = n.status.capacity?.memory {
                        Text("mem \(Self.humanMemory(mem))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let os = n.status.nodeInfo?.osImage {
                    Text(os)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Pods

    private var podsCard: some View {
        GroupBox("Pods") {
            if let pods = detail?.pods, !pods.isEmpty {
                let byPhase = Dictionary(grouping: pods) { $0.status.phase ?? "Unknown" }
                let byNs = Dictionary(grouping: pods) { $0.metadata.namespace ?? "default" }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ForEach(byPhase.keys.sorted(), id: \.self) { phase in
                            statPill(phase, "\(byPhase[phase]?.count ?? 0)",
                                     color: phaseColor(phase))
                        }
                        Spacer()
                        Text("\(pods.count) total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(byNs.keys.sorted(), id: \.self) { ns in
                            HStack {
                                Text(ns).font(.callout.monospaced())
                                Spacer()
                                Text("\(byNs[ns]?.count ?? 0)")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(4)
            } else {
                Text(detail?.loading == true ? "Loading…" : "No pods.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase {
        case "Running": return .green
        case "Pending": return .orange
        case "Succeeded": return .blue
        case "Failed": return .red
        default: return .gray
        }
    }

    // MARK: - Kubeconfig

    private var kubeconfigCard: some View {
        GroupBox("Kubeconfig") {
            VStack(alignment: .leading, spacing: 6) {
                Text(cluster.kubeconfigPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button {
                        copy("export KUBECONFIG=\(cluster.kubeconfigPath)")
                    } label: {
                        Label("Copy export command", systemImage: "doc.on.doc")
                    }
                    Spacer()
                }
            }
            .padding(6)
        }
    }

    private func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    /// Format a k8s memory quantity (e.g. "16307012Ki") as a readable GiB/MiB
    /// string. Falls back to the raw value if it can't be parsed.
    static func humanMemory(_ raw: String) -> String {
        guard let mib = QuantityParser.memoryMiB(raw) else { return raw }
        if mib >= 1024 {
            return String(format: "%.1f GiB", mib / 1024)
        }
        return String(format: "%.0f MiB", mib)
    }

    // MARK: - Bits

    private func errorBanner(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(err)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
        )
    }

    private func metaPill(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).foregroundStyle(.secondary)
            Text(v).bold()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.secondary.opacity(0.12))
        )
    }

    private func statPill(_ label: String, _ value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.secondary.opacity(0.10))
        )
    }
}
