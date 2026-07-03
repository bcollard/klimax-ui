import SwiftUI

/// Detail view shown while a `kind` cluster is being created (and after, if it
/// failed). Streams the live `klimax cluster create` log and surfaces klimax's
/// node-version mismatch warning when it fires.
struct ClusterCreatingView: View {
    @Bindable var model: AppModel
    let creation: AppModel.Creation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let warning = creation.versionWarning {
                        warningBanner(warning)
                    }
                    LogConsoleView(
                        title: "Creation log",
                        text: creation.log.isEmpty ? "Starting…" : creation.log,
                        maxHeight: 520,
                        followTail: creation.running
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(creation.name).font(.largeTitle.bold())
                HStack(spacing: 8) {
                    statusIcon
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if creation.failed {
                Button {
                    model.creation = nil
                    model.selection = nil
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if creation.running {
            ProgressView().controlSize(.small)
        } else if creation.failed {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    private var statusText: String {
        if creation.running { return "Creating kind cluster…" }
        if creation.failed { return "Creation failed" }
        return "Created"
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Kind node version mismatch")
                    .font(.callout.bold())
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.15))
        )
    }
}
