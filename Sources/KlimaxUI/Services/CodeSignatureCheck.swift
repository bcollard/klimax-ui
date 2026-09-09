import Foundation
import Observation

/// Result of verifying the *running* app bundle's Developer ID signature and
/// Apple notarization.
struct CodeSignatureStatus: Sendable, Hashable {
    let signingAuthority: String?
    let teamIdentifier: String?
    let isValidSignature: Bool
    let isNotarized: Bool
    let gatekeeperSource: String?
    /// True when this Mac has Gatekeeper assessment turned off
    /// (`spctl --master-disable`), which makes "accepted" meaningless.
    let gatekeeperDisabled: Bool
    let bundlePath: String
    let error: String?

    /// An ad-hoc signature (what `./build.sh` produces for local development)
    /// verifies fine but has no authority chain and no team — worth calling out
    /// separately from a genuinely broken signature.
    var isAdHoc: Bool { isValidSignature && signingAuthority == nil && teamIdentifier == nil }
}

/// Confirms this copy of the app is genuinely signed by the developer and
/// notarized by Apple. The signature and the stapled notarization ticket travel
/// inside the `.app` bundle and are checked against Apple's public roots, which
/// every Mac already trusts — so the answer is the same on anyone's machine,
/// offline, using none of the developer's credentials.
///
/// It is deliberately *not* a build-provenance check: it says nothing about
/// which source commit produced this binary. That would need source-to-binary
/// attestation (Sigstore/SLSA from CI), which is a change to how releases are
/// built, not a Diagnostics-pane feature.
enum CodeSignatureCheck {
    /// Blocking — four `Process` round-trips. Call off the main actor.
    static func run() -> CodeSignatureStatus {
        let path = Bundle.main.bundlePath

        let verify = shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", path])
        // -dvvv (not the default -dv) is what makes codesign print the
        // Authority= chain at all.
        let info = shell("/usr/bin/codesign", ["-dvvv", path])
        let gatekeeper = shell("/usr/sbin/spctl", ["-a", "-vv", path])
        // The stapled notarization ticket is checked directly rather than only
        // through spctl: on a Mac with Gatekeeper assessment disabled spctl
        // accepts everything, and we don't want that to decide the answer.
        let stapled = shell("/usr/bin/xcrun", ["stapler", "validate", path])

        var authority: String?
        var teamID: String?
        for line in info.output.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            // The first Authority= line is the leaf certificate; the rest are
            // the intermediates up to Apple's root.
            if authority == nil, line.hasPrefix("Authority=") {
                authority = String(line.dropFirst("Authority=".count))
            }
            if line.hasPrefix("TeamIdentifier=") {
                let value = String(line.dropFirst("TeamIdentifier=".count))
                teamID = value == "not set" ? nil : value
            }
        }
        // An ad-hoc signature reports "Signature=adhoc" and no authority chain.
        if info.output.contains("Signature=adhoc") { authority = nil }

        var gatekeeperSource: String?
        for line in gatekeeper.output.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("source=") {
                gatekeeperSource = String(line.dropFirst("source=".count))
            }
        }
        let accepted = gatekeeper.output.contains(": accepted")
        let gatekeeperDisabled = gatekeeper.output.contains("override=security disabled")
        let isNotarized = stapled.status == 0
            || (gatekeeperSource?.contains("Notarized") ?? false)

        let error: String?
        if verify.status != 0 {
            error = verify.output.isEmpty ? "codesign verification failed" : verify.output
        } else if !accepted {
            error = gatekeeper.output.isEmpty ? "Gatekeeper rejected this app" : gatekeeper.output
        } else {
            error = nil
        }

        return CodeSignatureStatus(
            signingAuthority: authority,
            teamIdentifier: teamID,
            isValidSignature: verify.status == 0,
            isNotarized: isNotarized,
            gatekeeperSource: gatekeeperSource,
            gatekeeperDisabled: gatekeeperDisabled,
            bundlePath: path,
            error: error
        )
    }

    private static func shell(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let pipe = Pipe()
        // codesign and spctl write their findings to stderr; merge the streams.
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Owns the integrity check's state for the Diagnostics tab. Kept separate from
/// `AppModel`: this is a fact about the app bundle on disk, not about klimax.
@MainActor
@Observable
final class CodeSignatureModel {
    private(set) var status: CodeSignatureStatus?
    private(set) var isChecking = false

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        status = await Task.detached(priority: .userInitiated) {
            CodeSignatureCheck.run()
        }.value
    }
}
