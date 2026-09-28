import SwiftUI

/// Aggregated, timestamped transcript of every action across the app, pinned to
/// the bottom of the detail area. Toggled by the "Console log panel" setting.
/// Complements the per-view "Last action" cards, which show only scoped logs.
struct ConsoleLogView: View {
    @Bindable var model: AppModel
    /// Folded down to just the header bar to reclaim vertical space.
    @State private var collapsed = false

    private var transcript: String { model.consoleTranscript }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
                } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(collapsed ? "Expand the console" : "Collapse the console")

                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text("Console")
                    .font(.subheadline.bold())
                Text("\(model.logRecords.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                Spacer()
                CopyButton(text: transcript)
                Button {
                    model.clearLog()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Clear the console")
                .disabled(transcript.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            }

            if !collapsed {
                Divider()
                scrollBody
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var scrollBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if transcript.isEmpty {
                    Text("No actions yet.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    Text(LogColorizer.attributed(transcript))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .overlay(alignment: .bottom) {
                            Color.clear.frame(height: 1).id(Self.tailID)
                        }
                }
            }
            .onChange(of: transcript) {
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(Self.tailID, anchor: .bottom)
                }
            }
        }
        .frame(height: 200)
    }

    private static let tailID = "console-tail"
}
