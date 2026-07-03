import SwiftUI

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var showNewClusterSheet = false
    @State private var newClusterName = ""

    var body: some View {
        List(selection: $model.selection) {
            Section {
                VMCard(model: model)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
            }

            Section {
                if model.clusters.isEmpty && model.provisioningClusterName == nil {
                    Text(
                        model.vm?.isRunning == true
                        ? "No clusters yet."
                        : "Start the VM to view clusters."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(model.clusters) { c in
                        ClusterRow(
                            cluster: c,
                            createdAt: model.clusterCreatedAt[c.name],
                            isCurrentContext: model.currentKubeContext == c.name
                        )
                        .tag(SidebarSelection.cluster(name: c.name))
                    }
                    if let name = model.provisioningClusterName {
                        ProvisioningRow(name: name, failed: model.creation?.failed == true)
                            .tag(SidebarSelection.cluster(name: name))
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Clusters")
                        .font(.headline)
                        .textCase(nil)
                    Button {
                        newClusterName = ""
                        showNewClusterSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.vm?.isRunning != true || model.inFlightAction != nil)
                    .help("Create a new kind cluster")
                    if model.clustersLoading {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                }
                .padding(.bottom, 6)
            }

            Section {
                if model.mirrors.isEmpty {
                    Text("No mirrors configured.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.mirrors, id: \.name) { m in
                        MirrorRow(mirror: m)
                            .tag(SidebarSelection.mirror(name: m.name))
                    }
                }
            } header: {
                Text("Registry mirrors")
                    .font(.headline)
                    .textCase(nil)
                    .padding(.bottom, 6)
            }

            Section {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                    Text(model.currentKubeContext ?? "no kube context")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(model.currentKubeContext == nil ? .tertiary : .secondary)
                .help("kubectl current-context")

                if let version = model.klimaxVersion {
                    Text(version)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showNewClusterSheet) {
            NewClusterSheet(model: model, isPresented: $showNewClusterSheet)
        }
    }
}

private struct ClusterRow: View {
    let cluster: KindCluster
    let createdAt: Date?
    var isCurrentContext: Bool = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(cluster.name)
                    if isCurrentContext {
                        Text("current")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                            .help("kubectl current-context")
                    }
                }
                if let createdAt {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(RelativeAge.format(since: createdAt, now: context.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } icon: {
            Image(systemName: "circle.grid.3x3.fill")
                .foregroundStyle(.blue)
        }
    }
}

private struct ProvisioningRow: View {
    let name: String
    let failed: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(failed ? "failed" : "creating…")
                    .font(.caption2)
                    .foregroundStyle(failed ? .red : .secondary)
            }
        } icon: {
            if failed {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
    }
}

private struct MirrorRow: View {
    let mirror: KlimaxConfig.Registries.Mirror

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                Text(mirror.remoteURL)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.purple)
        }
    }

    private var displayName: String {
        // Mirror names are like "registry-dockerio" — trim prefix for readability.
        mirror.name.hasPrefix("registry-")
            ? String(mirror.name.dropFirst("registry-".count))
            : mirror.name
    }
}

private struct VMCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.selection = nil
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        if let img = AppAssets.logo {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.vm?.name ?? "klimax")
                                .font(.headline)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(model.vm?.isRunning == true ? .green : .gray)
                                    .frame(width: 7, height: 7)
                                Text(statusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "house")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    if let vm = model.vm {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            metaRow("CPUs", vm.lima?.cpus.map(String.init) ?? "—")
                            metaRow("Memory", vm.lima?.memory ?? "—")
                            metaRow("Disk", vm.lima?.disk ?? "—")
                            if let loadAvg = model.guestStats?.loadAvg {
                                let parts = loadAvg.split(separator: " ")
                                let load = parts.prefix(3).joined(separator: " ")
                                metaRow("Load", load, valueColor: loadColor(parts.first))
                            }
                            if let total = model.guestStats?.memTotalKB,
                               let avail = model.guestStats?.memAvailableKB
                            {
                                let usedGiB = Double(total - avail) / 1024 / 1024
                                let totalGiB = Double(total) / 1024 / 1024
                                let ratio = total > 0 ? Double(total - avail) / Double(total) : 0
                                HStack {
                                    Text("Used")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Spacer()
                                    // Only the current usage is tinted; the total
                                    // allocation stays in the default color.
                                    (
                                        Text(String(format: "%.1f", usedGiB))
                                            .foregroundColor(usageColor(ratio, warn: 0.7, crit: 0.9))
                                        // Pin the total to secondary so it stays a constant
                                        // dark grey instead of following the window's
                                        // key-state (active=white / inactive=grey) dimming.
                                        + Text(String(format: " / %.1f GiB", totalGiB))
                                            .foregroundColor(.secondary)
                                    )
                                    .font(.caption.monospacedDigit())
                                    .textSelection(.enabled)
                                }
                            }
                            if let ip = model.guestLima0IP {
                                metaRow("IP address (lima0)", ip)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show overview")

            HStack(spacing: 6) {
                if let label = model.inFlightAction {
                    ProgressView().controlSize(.mini)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                } else {
                    if model.vm?.isRunning == true {
                        Button(role: .destructive) {
                            Task { await model.stopVM() }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .controlSize(.small)
                    } else {
                        Button {
                            Task { await model.startVM() }
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
            .disabled(model.inFlightAction != nil)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var statusText: String {
        switch model.vm?.runtime {
        case .running: return "Running"
        case .stopped, .none: return "Stopped"
        case .unknown: return "Unknown"
        }
    }

    private func metaRow(_ k: String, _ v: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(k)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Text(v)
                .font(.caption.monospacedDigit())
                .foregroundStyle(valueColor ?? .primary)
                .textSelection(.enabled)
        }
    }

    /// Traffic-light color for a 0…1 usage ratio.
    private func usageColor(_ ratio: Double, warn: Double, crit: Double) -> Color {
        if ratio >= crit { return .red }
        if ratio >= warn { return .orange }
        return .green
    }

    /// Color the 1-minute load average relative to the VM's core count
    /// (load == cores means fully saturated). Nil when we can't compute a ratio.
    private func loadColor(_ oneMinuteField: Substring?) -> Color? {
        guard let oneMinuteField, let load = Double(oneMinuteField),
              let cores = model.vm?.lima?.cpus, cores > 0
        else { return nil }
        return usageColor(load / Double(cores), warn: 0.7, crit: 1.0)
    }
}

