import SwiftUI
import AppKit

/// A scrollable monospaced log box with a copy-to-clipboard button pinned to
/// the upper-right corner and light per-line syntax coloring. Used for the
/// "Last action" cards and the live `kind create` log.
struct LogConsoleView: View {
    let title: String
    let text: String
    var maxHeight: CGFloat? = 200
    /// Auto-scroll to the newest line as `text` grows (for live logs).
    var followTail: Bool = false

    var body: some View {
        GroupBox {
            ZStack(alignment: .topTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(LogColorizer.attributed(text))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            // Trailing anchor we can scroll to.
                            .overlay(alignment: .bottom) {
                                Color.clear.frame(height: 1).id(Self.tailID)
                            }
                    }
                    .frame(maxHeight: maxHeight)
                    .onChange(of: text) {
                        guard followTail else { return }
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(Self.tailID, anchor: .bottom)
                        }
                    }
                }
                CopyButton(text: text)
                    .padding(6)
            }
        } label: {
            Text(title)
        }
    }

    private static let tailID = "log-tail"
}

/// A small button that copies `text` and briefly flips to a checkmark.
struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .padding(5)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(copied ? "Copied" : "Copy to clipboard")
        .disabled(text.isEmpty)
    }
}

/// Colors log lines by simple content heuristics — enough to make kind's
/// progress output and any errors/warnings pop, without a real lexer.
enum LogColorizer {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            var piece = AttributedString(String(line))
            if let color = color(for: line) {
                piece.foregroundColor = color
            }
            result += piece
            if i < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private static func color(for line: Substring) -> Color? {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("fatal")
            || line.contains("✗") || lower.contains("level=error") {
            return .red
        }
        if lower.contains("unsupported") || lower.contains("warn") || line.contains("⚠") {
            return .orange
        }
        if line.contains("✓") || lower.contains("set kubectl context")
            || lower.contains("have a nice day") || lower.contains("ready") {
            return .green
        }
        // Section markers / debug chatter fade back.
        if line.hasPrefix("──") || lower.contains("level=debug") {
            return .secondary
        }
        return nil
    }
}
