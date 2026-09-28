import Foundation

/// Talks to a cluster's metrics.k8s.io API via `kubectl get --raw`.
/// metrics-server must be installed; without it the API returns 404.
struct MetricsClient: Sendable {
    let kubeconfigPath: String

    enum MetricsError: Error, LocalizedError {
        case notAvailable
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "metrics-server not reachable"
            case .decode(let m): return "Failed to decode metrics: \(m)"
            }
        }
    }

    func fetchNodes() async throws -> [NodeMetric] {
        let raw = try await rawGet("/apis/metrics.k8s.io/v1beta1/nodes")
        let list = try decode(NodeMetricsList.self, from: raw)
        return list.items.compactMap { item -> NodeMetric? in
            guard let cpu = QuantityParser.cpuMillicores(item.usage.cpu),
                  let mem = QuantityParser.memoryMiB(item.usage.memory),
                  let ts = parseTimestamp(item.timestamp)
            else { return nil }
            return NodeMetric(
                name: item.metadata.name,
                timestamp: ts,
                cpuMillicores: cpu,
                memoryMiB: mem
            )
        }
    }

    func fetchPods() async throws -> [PodMetric] {
        let raw = try await rawGet("/apis/metrics.k8s.io/v1beta1/pods")
        let list = try decode(PodMetricsList.self, from: raw)
        return list.items.compactMap { item -> PodMetric? in
            // Sum containers within the pod.
            var cpuSum = 0.0
            var memSum = 0.0
            for c in item.containers {
                guard let cpu = QuantityParser.cpuMillicores(c.usage.cpu),
                      let mem = QuantityParser.memoryMiB(c.usage.memory)
                else { continue }
                cpuSum += cpu
                memSum += mem
            }
            guard let ts = parseTimestamp(item.timestamp) else { return nil }
            return PodMetric(
                name: item.metadata.name,
                namespace: item.metadata.namespace ?? "",
                timestamp: ts,
                cpuMillicores: cpuSum,
                memoryMiB: memSum
            )
        }
    }

    private func rawGet(_ path: String) async throws -> Data {
        let result = try await ProcessRunner.run("kubectl", [
            "--kubeconfig", kubeconfigPath,
            "get", "--raw", path,
        ])
        guard result.ok else {
            throw MetricsError.notAvailable
        }
        return Data(result.stdout.utf8)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MetricsError.decode(error.localizedDescription)
        }
    }

    private func parseTimestamp(_ s: String) -> Date? {
        // metrics-server emits RFC3339 timestamps like "2026-05-25T12:53:46Z".
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }
}

// MARK: - On-the-wire shapes

private struct NodeMetricsList: Decodable, Sendable {
    let items: [NodeItem]
    struct NodeItem: Decodable, Sendable {
        let metadata: Meta
        let timestamp: String
        let usage: Usage
    }
}

private struct PodMetricsList: Decodable, Sendable {
    let items: [PodItem]
    struct PodItem: Decodable, Sendable {
        let metadata: Meta
        let timestamp: String
        let containers: [Container]
        struct Container: Decodable, Sendable {
            let name: String
            let usage: Usage
        }
    }
}

private struct Meta: Decodable, Sendable {
    let name: String
    let namespace: String?
}

private struct Usage: Decodable, Sendable {
    let cpu: String
    let memory: String
}
