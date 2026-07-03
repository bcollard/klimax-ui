import SwiftUI

struct MirrorDetailView: View {
    @Bindable var model: AppModel
    let mirror: KlimaxConfig.Registries.Mirror

    private var cacheSize: AppModel.MirrorCacheSize? {
        model.mirrorCacheSizes[mirror.name]
    }

    /// The registry host that pulls get rewritten from. klimax aliases
    /// registry-1.docker.io to the user-facing "docker.io", so surface that.
    private var interceptedHost: String {
        let host = URL(string: mirror.remoteURL)?.host ?? mirror.remoteURL
        return host.contains("docker.io") ? "docker.io" : host
    }

    /// Ties the "Intercepts" value to the same term in the Usage paragraph.
    static let hostColor: Color = .blue

    /// A concrete image reference for the intercepted registry, for the example.
    private var exampleImage: String {
        switch interceptedHost {
        case "docker.io": return "docker.io/library/nginx:latest"
        case "quay.io": return "quay.io/prometheus/node-exporter:latest"
        case "gcr.io": return "gcr.io/google-containers/pause:3.9"
        default: return "\(interceptedHost)/<image>:<tag>"
        }
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
                        row("Remote URL", mirror.remoteURL, mono: true, valueColor: .secondary)
                        Divider().padding(.vertical, 4)
                        row("Intercepts", interceptedHost, mono: true, valueColor: Self.hostColor,
                            help: "Image references for this registry host are rewritten to the mirror by each kind node's containerd (via /etc/containerd/certs.d).")
                        Text("Remote URL is read from your klimax config file.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                    }
                    .padding(8)
                }
                GroupBox("Usage") {
                    VStack(alignment: .leading, spacing: 10) {
                        (
                            Text("Any image pulled from ")
                            + Text(interceptedHost).foregroundColor(Self.hostColor).bold()
                            + Text(" inside the cluster is transparently served through this mirror — no changes to your manifests.")
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Example")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text("A pod using `\(exampleImage)` is fetched once, cached below, and served from that cache on the next pull — even from a fresh cluster — instead of hitting the internet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                }
                cacheCard
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

    private func row(_ k: String, _ v: String, mono: Bool = false,
                     valueColor: Color? = nil, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Text(k)
                    .foregroundStyle(.secondary)
                if let help {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help(help)
                }
            }
            .frame(width: 140, alignment: .leading)
            Text(v)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(valueColor ?? .primary)
                .textSelection(.enabled)
        }
    }
}
