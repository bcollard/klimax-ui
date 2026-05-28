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
                if model.clusters.isEmpty {
                    Text(
                        model.vm?.isRunning == true
                        ? "No clusters yet."
                        : "Start the VM to view clusters."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(model.clusters) { c in
                        ClusterRow(cluster: c)
                            .tag(SidebarSelection.cluster(name: c.name))
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
            }

            if let version = model.klimaxVersion {
                Section {
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

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(cluster.name)
                Text("num \(cluster.num) · api :\(cluster.apiPort)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "circle.grid.3x3.fill")
                .foregroundStyle(.blue)
        }
    }
}

private struct MirrorRow: View {
    let mirror: KlimaxConfig.Registries.Mirror

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                Text(":\(mirror.port) → \(shortRemote)")
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

    private var shortRemote: String {
        URL(string: mirror.remoteURL)?.host ?? mirror.remoteURL
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
                            if let ip = model.guestLima0IP {
                                metaRow("lima0", ip)
                            }
                            if let load = model.guestStats?.loadAvg?.split(separator: " ").prefix(3).joined(separator: " ") {
                                metaRow("Load", load)
                            }
                            if let total = model.guestStats?.memTotalKB,
                               let avail = model.guestStats?.memAvailableKB
                            {
                                let usedGiB = Double(total - avail) / 1024 / 1024
                                let totalGiB = Double(total) / 1024 / 1024
                                metaRow("Used", String(format: "%.1f / %.1f GiB", usedGiB, totalGiB))
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
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("Refresh")
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

    private func metaRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Text(v)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}

