import Foundation

/// Wrapper around the `klimax` CLI. Read operations prefer structured output;
/// write operations are fire-and-forget with combined stdout/stderr captured for logging.
enum KlimaxCLI {
    static let executable = "klimax"

    enum CLIError: Error, LocalizedError {
        case notInstalled
        case command(String, Int32, String)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                return "klimax CLI not found in PATH"
            case .command(let cmd, let code, let stderr):
                return "klimax \(cmd) exited \(code): \(stderr)"
            case .decode(let m):
                return "Failed to decode klimax output: \(m)"
            }
        }
    }

    static func listClusters() async throws -> [KindCluster] {
        let result = try await ProcessRunner.run(executable, ["cluster", "list", "-o", "json"])
        guard result.ok else {
            throw CLIError.command("cluster list", result.exitCode, result.stderr)
        }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if stdout.isEmpty || stdout == "null" { return [] }
        guard let data = stdout.data(using: .utf8) else {
            throw CLIError.decode("non-utf8 output")
        }
        do {
            return try JSONDecoder().decode([KindCluster].self, from: data)
        } catch {
            throw CLIError.decode(error.localizedDescription)
        }
    }

    /// Start (or finish provisioning) the VM. Long-running.
    static func up() async throws -> ProcessResult {
        try await ProcessRunner.run(executable, ["up"])
    }

    /// Stop the VM.
    static func down() async throws -> ProcessResult {
        try await ProcessRunner.run(executable, ["down"])
    }

    /// Create a new kind cluster with the given name.
    static func createCluster(name: String) async throws -> ProcessResult {
        try await ProcessRunner.run(executable, ["cluster", "create", name])
    }

    /// Set/overwrite a node label on an existing cluster (klimax 0.1.35+):
    /// `klimax cluster label <name> -l key=value`. This is klimax's canonical
    /// relabel path (shared with create-time labeling); prefer it over a raw
    /// kubectl label so behavior stays consistent.
    static func labelCluster(name: String, key: String, value: String) async throws -> ProcessResult {
        try await ProcessRunner.run(executable, ["cluster", "label", name, "-l", "\(key)=\(value)"])
    }

    /// Delete a kind cluster by name. `-y` skips the interactive confirmation
    /// prompt klimax shows by default (which would otherwise hang our Process).
    static func deleteCluster(name: String) async throws -> ProcessResult {
        try await ProcessRunner.run(executable, ["cluster", "delete", name, "-y"])
    }

    /// Run `klimax doctor -o json`, optionally applying the repairs klimax can
    /// perform itself (`--fix`).
    ///
    /// The report is on stdout; klimax's own logging goes to stderr, so we
    /// decode stdout alone. `doctor` exits 0 even when checks fail (the report
    /// carries `ok: false`), but we decode regardless of exit code so a future
    /// klimax that starts signalling failure through the exit status still
    /// renders its report.
    ///
    /// `--fix` shells out to `sudo` for the macOS route repair. Launched from
    /// the app bundle there is no controlling terminal, so sudo fails fast with
    /// "no tty present" rather than blocking on a password prompt — that lands
    /// in the check's `fixError` and the UI offers the command to run by hand.
    static func doctor(fix: Bool = false) async throws -> DoctorReport {
        var args = ["doctor", "-o", "json"]
        if fix { args.append("--fix") }
        let result = try await ProcessRunner.run(executable, args)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = stdout.data(using: .utf8), !stdout.isEmpty else {
            throw CLIError.command("doctor", result.exitCode, result.stderr)
        }
        do {
            return try JSONDecoder().decode(DoctorReport.self, from: data)
        } catch {
            throw CLIError.decode(error.localizedDescription)
        }
    }

    /// Return klimax version string, e.g. "klimax 0.1.25".
    static func version() async throws -> String {
        let result = try await ProcessRunner.run(executable, ["version"])
        guard result.ok else {
            throw CLIError.command("version", result.exitCode, result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
