import SwiftUI

struct MirrorDetailView: View {
    @Bindable var model: AppModel
    let mirror: KlimaxConfig.Registries.Mirror

    private var cacheSize: AppModel.MirrorCacheSize? {
        model.mirrorCacheSizes[mirror.name]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mirror.name).font(.largeTitle.bold())
                    Text("Pull-through registry mirror")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Divider()
                GroupBox("Configuration") {
                    VStack(alignment: .leading, spacing: 6) {
                        row("Listen port", "\(mirror.port)")
                        row("Remote URL", mirror.remoteURL, mono: true)
                        Divider().padding(.vertical, 4)
                        row("Pull via guest",
                            "kind-control-plane → \(mirror.name):\(mirror.port)",
                            mono: true)
                    }
                    .padding(8)
                }
                cacheCard
                GroupBox("Usage") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pulls from \(URL(string: mirror.remoteURL)?.host ?? mirror.remoteURL) are routed through this mirror by the kind cluster's containerd config — no client-side changes required.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: mirror.name) {
            await model.measureMirrorCache(mirror)
        }
    }

    private var cacheCard: some View {
        GroupBox("Cache storage") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Disk usage")
                        .frame(width: 140, alignment: .leading)
                        .foregroundStyle(.secondary)
                    cacheUsageView
                    Spacer()
                    Button {
                        Task { await model.measureMirrorCache(mirror) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .help("Re-measure cache size and image count")
                }
                if case .measured(_, let tags, let repos, _) = cacheSize {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Images")
                            .frame(width: 140, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(imageCountText(tags: tags, repos: repos))
                            .font(.body.monospacedDigit())
                            .textSelection(.enabled)
                    }
                }
                if let path = cachePath {
                    row("Path", path, mono: true)
                }
            }
            .padding(8)
        }
    }

    private func imageCountText(tags: Int?, repos: Int?) -> String {
        switch (tags, repos) {
        case let (t?, r?):
            return "\(t) tag\(t == 1 ? "" : "s") across \(r) repo\(r == 1 ? "" : "s")"
        case let (t?, nil):
            return "\(t) tag\(t == 1 ? "" : "s")"
        default:
            return "—"
        }
    }

    @ViewBuilder
    private var cacheUsageView: some View {
        switch cacheSize {
        case .measuring, .none:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Measuring…")
                    .foregroundStyle(.secondary)
            }
        case .measured(let bytes, _, _, _):
            Text(formatBytes(bytes))
                .font(.body.monospacedDigit())
                .textSelection(.enabled)
        case .missing:
            Text("not yet populated")
                .foregroundStyle(.secondary)
        case .storedInGuest:
            Text("stored inside the VM (configure cacheStorage: host to measure from here)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var cachePath: String? {
        switch cacheSize {
        case .measured(_, _, _, let path), .missing(let path): return path
        default: return nil
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(v)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}
