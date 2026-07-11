import SwiftUI

struct ClusterDetailView: View {
    @Bindable var model: AppModel
    let cluster: KindCluster
    @State private var tab: Tab = .info
    @State private var showAddLabel = false
    @State private var newLabelKey = ""
    @State private var newLabelValue = ""
    @State private var labelError: String?

    enum Tab: Hashable { case info, services, metrics }

    private var detail: AppModel.ClusterDetail? {
        if model.clusterDetail?.cluster.name == cluster.name {
            return model.clusterDetail
        }
        return nil
    }

    /// Which action log this view surfaces: the Metrics tab shows metrics-server
    /// ops, the other tabs show the cluster's lifecycle actions.
    private var logScope: LogScope {
        tab == .metrics ? .metrics(cluster.name) : .cluster(cluster.name)
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
                .padding(.top, 10)
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
                        podsCard
                        nodesCard
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
                    if let rec = model.latestLog(for: logScope) {
                        LogConsoleView(
                            title: "Last action log",
                            text: rec.text,
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
            VStack(alignment: .leading, spacing: 8) {
                Text(cluster.name).font(.largeTitle.bold())
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 12) {
                        if let fleet = nodeLabels?[Self.fleetLabelKey] {
                            fleetBadge(fleet)
                        }
                        if let v = detail?.serverVersion {
                            metaPill("k8s", v)
                        }
                        if let createdAt = model.clusterCreatedAt[cluster.name] {
                            metaPill("age", RelativeAge.format(since: createdAt, now: context.date))
                        }
                        if let region = nodeLabels?[Self.regionLabelKey] {
                            metaPill("region", region)
                        }
                        if let zone = nodeLabels?[Self.zoneLabelKey] {
                            metaPill("zone", zone)
                        }
                    }
                    .font(.callout)
                }
                labelsRow
            }
            Spacer()
            if detail?.loading == true {
                ProgressView().controlSize(.small)
            }
            if model.currentKubeContext == cluster.name {
                Label("Current context", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("kubectl current-context is \(cluster.name)")
            } else {
                Button {
                    Task { await model.useContext(for: cluster) }
                } label: {
                    Label("Switch to context", systemImage: "arrow.right.circle")
                }
                .disabled(model.inFlightAction != nil)
                .help("Set kubectl's current-context to \(cluster.name)")
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

    // MARK: - Labels

    /// Node labels (same across nodes) for the loaded cluster.
    private var nodeLabels: [String: String]? {
        detail?.nodes.first?.metadata.labels
    }

    /// Wrapping row of node-label pills under the title, plus an add button.
    private var labelsRow: some View {
        FlowLayout(spacing: 6) {
            if let labels = nodeLabels {
                // fleet + region/zone are promoted to the meta line above.
                let rest = AppModel.displayLabels(labels).filter {
                    $0.key != Self.regionLabelKey
                        && $0.key != Self.zoneLabelKey
                        && $0.key != Self.fleetLabelKey
                }
                ForEach(rest, id: \.key) { pair in
                    metaPill(Self.shortLabelKey(pair.key), pair.value)
                }
            }
            addLabelButton
        }
    }

    static let fleetLabelKey = "klimax.dev/fleet"
    static let regionLabelKey = "topology.kubernetes.io/region"
    static let zoneLabelKey = "topology.kubernetes.io/zone"

    /// Fleet gets a distinct filled badge with the stack icon so it stands out
    /// from the plain grey label pills.
    private func fleetBadge(_ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "square.stack.3d.up.fill")
            Text("fleet").foregroundStyle(.white.opacity(0.75))
            Text(value).bold()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.blue))
        .help("Fleet: \(value)")
    }

    /// Dashed-blue "Add label" chip — mirrors the New Cluster tile's dashed
    /// border, sized like the label pills so its text aligns with them.
    private var addLabelButton: some View {
        Button {
            newLabelKey = ""
            newLabelValue = ""
            labelError = nil
            showAddLabel = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add label")
            }
            .font(.caption)
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(
                Capsule().strokeBorder(
                    Color.blue.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(model.inFlightAction != nil || (detail?.nodes.isEmpty ?? true))
        .help("Add a node label to every node")
        .popover(isPresented: $showAddLabel, arrowEdge: .bottom) { addLabelForm }
    }

    private var addLabelForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add node label").font(.headline)
            Text("Applied to every node in the cluster.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("key (e.g. klimax.dev/fleet)", text: $newLabelKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitLabel)
            TextField("value", text: $newLabelValue)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submitLabel)
            if let labelError {
                Label(labelError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddLabel = false }
                Button("Add") { submitLabel() }
                    .disabled(newLabelKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    /// Validate on Enter/Add: reject invalid Kubernetes label keys/values with
    /// inline feedback; only apply (and close) when the pair is valid.
    private func submitLabel() {
        let key = newLabelKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = newLabelValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Self.validateLabel(key: key, value: value) {
            labelError = error
            return
        }
        labelError = nil
        showAddLabel = false
        Task { await model.addLabel(to: cluster, key: key, value: value) }
    }

    /// Kubernetes label validation (mirrors klimax's ValidateLabels): optional
    /// DNS-subdomain prefix + "/" + a ≤63-char name segment; value is empty or a
    /// ≤63-char segment. Returns a human-readable error, or nil when valid.
    static func validateLabel(key: String, value: String) -> String? {
        guard !key.isEmpty else { return "Key is required." }
        let segment = "^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$"
        let name: String
        let slashParts = key.split(separator: "/", omittingEmptySubsequences: false)
        switch slashParts.count {
        case 1:
            name = String(slashParts[0])
        case 2:
            let prefix = String(slashParts[0])
            name = String(slashParts[1])
            let dns = "^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$"
            if prefix.isEmpty || prefix.count > 253
                || prefix.range(of: dns, options: .regularExpression) == nil {
                return "Invalid key prefix “\(prefix)”."
            }
        default:
            return "Key may contain at most one “/”."
        }
        if name.isEmpty || name.count > 63
            || name.range(of: segment, options: .regularExpression) == nil {
            return "Invalid key name “\(name)” (letters, digits, -_. ; ≤63 chars)."
        }
        if !value.isEmpty,
           value.count > 63 || value.range(of: segment, options: .regularExpression) == nil {
            return "Invalid value “\(value)” (letters, digits, -_. ; ≤63 chars)."
        }
        return nil
    }

    /// Shorten a label key to its last path segment for compact pills
    /// (klimax.dev/fleet → fleet, topology.kubernetes.io/region → region).
    static func shortLabelKey(_ key: String) -> String {
        key.split(separator: "/").last.map(String.init) ?? key
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
                        Text("\(pods.count) pods total")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Namespace")
                            Spacer()
                            Text("Pods")
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
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
