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

    /// Return klimax version string, e.g. "klimax 0.1.25".
    static func version() async throws -> String {
        let result = try await ProcessRunner.run(executable, ["version"])
        guard result.ok else {
            throw CLIError.command("version", result.exitCode, result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
