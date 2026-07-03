import SwiftUI
import AppKit

/// Default screen — shows when no sidebar item is selected. Acts as a dashboard
/// listing clusters and registry mirrors, both clickable to drill into details.
struct OverviewDetailView: View {
    @Bindable var model: AppModel
    @State private var showNewClusterSheet = false
    @State private var showDeleteAllConfirm = false

    private var clustersHeaderTrailing: AnyView {
        AnyView(
            HStack(spacing: 8) {
                if model.clustersLoading {
                    ProgressView().controlSize(.mini)
                }
                if !model.clusters.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label("Delete all", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(model.inFlightAction != nil)
                    .help("Delete every kind cluster")
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                clustersSection
                mirrorsSection
                if model.vm?.isRunning == true {
                    VMChartsView(model: model)
                }
                if !model.actionLog.isEmpty {
                    actionLogCard
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showNewClusterSheet) {
            NewClusterSheet(model: model, isPresented: $showNewClusterSheet)
        }
        .confirmationDialog(
            "Delete all \(model.clusters.count) clusters?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete all clusters", role: .destructive) {
                Task { await model.deleteAllClusters() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This tears down every kind cluster in the VM. This cannot be undone.")
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            if let img = AppAssets.logo {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(radius: 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("klimax").font(.largeTitle.bold())
                configRow
            }
            Spacer()
        }
    }

    private var configRow: some View {
        let url = InstanceDiscovery.configFile()
        return HStack(spacing: 8) {
            Text(prettyPath(url.path))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "pencil")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("Open \(url.lastPathComponent) in the default editor")
        }
    }

    /// Replace the user's home directory prefix with `~` for compact display.
    private func prettyPath(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if p.hasPrefix(home) {
            return "~" + p.dropFirst(home.count)
        }
        return p
    }

    // MARK: - Clusters

    private var clustersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Clusters",
                count: model.clusters.count,
                trailing: clustersHeaderTrailing
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(model.clusters) { c in
                    ClusterCard(cluster: c, fleet: model.fleet(of: c.name)) {
                        model.selection = .cluster(name: c.name)
                    }
                }
                if let name = model.provisioningClusterName {
                    ProvisioningClusterCard(
                        name: name,
                        failed: model.creation?.failed == true
                    ) {
                        model.selection = .cluster(name: name)
                    }
                }
                NewClusterCard(
                    disabled: model.vm?.isRunning != true || model.inFlightAction != nil,
                    disabledReason: model.vm?.isRunning == true ? nil : "Start the VM first"
                ) {
                    showNewClusterSheet = true
                }
            }
        }
    }

    // MARK: - Mirrors

    private var mirrorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Registry mirrors", count: model.mirrors.count, trailing: nil)
            if model.mirrors.isEmpty {
                emptyCard("No mirrors configured.")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(model.mirrors, id: \.name) { m in
                        MirrorCard(mirror: m) {
                            model.selection = .mirror(name: m.name)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action log

    private var actionLogCard: some View {
        LogConsoleView(title: "Last action", text: model.actionLog, maxHeight: 200)
    }

    // MARK: - Bits

    private func sectionHeader(title: String, count: Int, trailing: AnyView?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.bold())
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
            if let trailing { trailing }
            Spacer()
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )
    }
}

// MARK: - Cards

private struct ClusterCard: View {
    let cluster: KindCluster
    var fleet: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "circle.grid.3x3.fill")
                        .foregroundStyle(.blue)
                    Text(cluster.name).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                HStack(spacing: 6) {
                    pill("num \(cluster.num)")
                    pill("api :\(cluster.apiPort)")
                    if let fleet {
                        pill("fleet \(fleet)")
                    }
                }
                Text(cluster.kubeconfigPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(hovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(hovering ? 0.25 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct MirrorCard: View {
    let mirror: KlimaxConfig.Registries.Mirror
    let action: () -> Void
    @State private var hovering = false

    private var displayName: String {
        mirror.name.hasPrefix("registry-")
            ? String(mirror.name.dropFirst("registry-".count))
            : mirror.name
    }

    private var remoteHost: String {
        URL(string: mirror.remoteURL)?.host ?? mirror.remoteURL
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.purple)
                    Text(displayName).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                HStack(spacing: 6) {
                    pill(":\(mirror.port)")
                    pill(remoteHost)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(hovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(hovering ? 0.25 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ProvisioningClusterCard: View {
    let name: String
    let failed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if failed {
                        Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(name).font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
                Text(failed ? "Creation failed — tap for log" : "Creating… tap to follow log")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(hovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(hovering ? 0.25 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct NewClusterCard: View {
    let disabled: Bool
    let disabledReason: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(disabled ? Color.secondary : Color.accentColor)
                Text("New cluster")
                    .font(.headline)
                    .foregroundStyle(disabled ? Color.secondary : Color.primary)
                if let disabledReason {
                    Text(disabledReason)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(hovering && !disabled ? 0.10 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color.secondary.opacity(hovering && !disabled ? 0.45 : 0.25),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(disabled ? (disabledReason ?? "Create a new kind cluster") : "Create a new kind cluster")
    }
}

private func pill(_ text: String) -> some View {
    Text(text)
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
}
