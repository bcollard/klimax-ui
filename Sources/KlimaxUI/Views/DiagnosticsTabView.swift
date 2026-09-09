import SwiftUI
import AppKit

/// Settings › Diagnostics. Two independent questions: is the klimax stack
/// healthy (`klimax doctor`), and is this copy of the app the one the developer
/// shipped (codesign + Gatekeeper).
struct DiagnosticsTabView: View {
    @Bindable var model: AppModel
    @State private var signature = CodeSignatureModel()

    var body: some View {
        Form {
            doctorSection
            integritySection
        }
        .formStyle(.grouped)
        .task {
            // Both checks are cheap and answer the question the user opened
            // this tab to ask, so run them on appear rather than making them
            // click twice. Re-runs are manual.
            if model.doctorReport == nil, !model.doctorRunning {
                await model.runDoctor()
            }
            if signature.status == nil {
                await signature.check()
            }
        }
    }

    // MARK: - klimax doctor

    @ViewBuilder
    private var doctorSection: some View {
        Section {
            if let report = model.doctorReport {
                ForEach(report.checks) { check in
                    DoctorCheckRow(check: check)
                }
            } else if let error = model.doctorError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if !model.doctorRunning {
                Text("Not run yet.").foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Run diagnostics") {
                    Task { await model.runDoctor() }
                }
                .controlSize(.small)
                .disabled(model.doctorRunning)

                if let report = model.doctorReport, !report.fixableFailures.isEmpty {
                    Button("Apply \(report.fixableFailures.count) fix\(report.fixableFailures.count == 1 ? "" : "es")") {
                        Task { await model.runDoctor(applyFixes: true) }
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .help("Runs klimax doctor --fix. The macOS route repair needs sudo, which an app bundle can't prompt for — if it fails, run the command in a terminal.")
                }

                if model.doctorRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let ranAt = model.doctorRanAt, !model.doctorRunning {
                    Text(ranAt, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("Health checks")
                if let report = model.doctorReport {
                    summaryBadge(report)
                }
            }
        } footer: {
            Text("""
                 Runs `klimax doctor`: the Lima hostagent, the VM, the macOS \
                 route to the kind bridge, Rosetta on both sides, the guest's \
                 no-NAT exemption and IP forwarding. Nothing here is polled — \
                 the probes are too heavy for a background loop.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryBadge(_ report: DoctorReport) -> some View {
        let (text, tint): (String, Color) = {
            if report.failureCount > 0 {
                return ("\(report.failureCount) failing", .red)
            }
            if report.warningCount > 0 {
                return ("\(report.warningCount) warning\(report.warningCount == 1 ? "" : "s")", .orange)
            }
            return ("all \(report.checks.count) passing", .green)
        }()
        return Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    // MARK: - App integrity

    @ViewBuilder
    private var integritySection: some View {
        Section {
            if let status = signature.status {
                LabeledContent("Signed by") {
                    Text(status.signingAuthority ?? (status.isAdHoc ? "ad-hoc (local build)" : "—"))
                        .font(.callout)
                        .foregroundStyle(status.signingAuthority == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                LabeledContent("Team ID") {
                    Text(status.teamIdentifier ?? "—")
                        .font(.callout.monospaced())
                        .foregroundStyle(status.teamIdentifier == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                        .textSelection(.enabled)
                }
                integrityRow(
                    ok: status.isValidSignature,
                    okText: status.isAdHoc ? "Signature valid (ad-hoc)" : "Signature valid",
                    badText: "Signature invalid"
                )
                integrityRow(
                    ok: status.isNotarized,
                    okText: "Notarized by Apple",
                    badText: status.isAdHoc ? "Not notarized (local build)" : "Not notarized",
                    warnOnly: status.isAdHoc
                )
                if let source = status.gatekeeperSource {
                    LabeledContent("Gatekeeper") {
                        Text(source).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if status.gatekeeperDisabled {
                    Label(
                        "Gatekeeper assessment is disabled on this Mac, so it would accept any app. The notarization result above comes from the ticket stapled to the bundle, not from Gatekeeper.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                if let err = status.error {
                    Text(err)
                        .font(.caption.monospaced())
                        .foregroundStyle(status.isAdHoc ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            } else {
                Text(signature.isChecking ? "Checking…" : "Not checked yet")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Re-check") { Task { await signature.check() } }
                    .controlSize(.small)
                    .disabled(signature.isChecking)
                if signature.isChecking { ProgressView().controlSize(.small) }
                Spacer()
                if let status = signature.status {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: status.bundlePath)]
                        )
                    } label: {
                        Image(systemName: "folder")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                    .help(status.bundlePath)
                }
            }
        } header: {
            Text("App integrity")
        } footer: {
            Text("""
                 Confirms this copy of Klimax is genuinely signed by the \
                 developer and notarized by Apple — verifiable on any Mac, \
                 offline, against Apple's public roots and none of the \
                 developer's credentials. It does not attest which source \
                 commit built the binary; that needs build provenance \
                 (Sigstore/SLSA), a different kind of check.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func integrityRow(ok: Bool, okText: String, badText: String, warnOnly: Bool = false) -> some View {
        let tint: Color = ok ? .green : (warnOnly ? .orange : .red)
        let symbol = ok ? "checkmark.seal.fill" : (warnOnly ? "exclamationmark.triangle.fill" : "xmark.seal.fill")
        return HStack(spacing: 5) {
            Image(systemName: symbol).imageScale(.small)
            Text(ok ? okText : badText)
        }
        .font(.callout)
        .foregroundStyle(tint)
    }
}

/// One `klimax doctor` check: status glyph, message, and — when it failed —
/// the detail and the command that repairs it.
private struct DoctorCheckRow: View {
    let check: DoctorCheck
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(check.title).font(.callout.weight(.medium))
                    Text(check.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                if let fixed = check.fixed {
                    Text(fixed ? "FIXED" : "FIX FAILED")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((fixed ? Color.green : Color.red).opacity(0.18)))
                        .foregroundStyle(fixed ? Color.green : Color.red)
                }
            }
            if let detail = check.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
            if let fixError = check.fixError, !fixError.isEmpty {
                Text(fixError)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.leading, 20)
            }
            if check.status != .ok, let fix = check.fix, !fix.isEmpty {
                HStack(spacing: 6) {
                    Text(fix)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.secondary.opacity(0.12))
                        )
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fix, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Copy the fix command")
                }
                .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch check.status {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch check.status {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        case .unknown: return .secondary
        }
    }
}
