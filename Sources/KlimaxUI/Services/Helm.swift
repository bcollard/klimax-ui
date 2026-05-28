import Foundation

/// Thin helm CLI wrapper scoped to a kubeconfig.
struct Helm: Sendable {
    let kubeconfigPath: String

    /// Install metrics-server into kube-system from the upstream Helm chart.
    /// Adds the repo if missing, then installs with `--kubelet-insecure-tls`
    /// which is required for kind clusters whose kubelet serves a self-signed cert.
    func installMetricsServer() async throws -> ProcessResult {
        // helm repo add is idempotent only on identical URLs; ignore failure if already present.
        _ = try? await ProcessRunner.run("helm", [
            "repo", "add", "metrics-server",
            "https://kubernetes-sigs.github.io/metrics-server/",
        ])
        _ = try? await ProcessRunner.run("helm", ["repo", "update", "metrics-server"])

        let installArgs = [
            "install", "metrics-server", "metrics-server/metrics-server",
            "-n", "kube-system",
            "--kubeconfig", kubeconfigPath,
            "--set", "args[0]=--kubelet-insecure-tls",
            "--wait", "--timeout", "120s",
        ]
        return try await ProcessRunner.run("helm", installArgs)
    }

    /// Uninstall metrics-server release. Returns process result for logging.
    func uninstallMetricsServer() async throws -> ProcessResult {
        try await ProcessRunner.run("helm", [
            "uninstall", "metrics-server",
            "-n", "kube-system",
            "--kubeconfig", kubeconfigPath,
        ])
    }
}
