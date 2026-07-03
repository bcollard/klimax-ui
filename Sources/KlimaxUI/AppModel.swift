import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // The single klimax VM. Klimax is designed around exactly one instance at a time.
    var vm: Instance?
    var config: KlimaxConfig?
    var klimaxVersion: String?

    // VM live state (probed over SSH when running).
    var guestStats: GuestSSH.GuestStats?
    var guestLima0IP: String?

    var clusters: [KindCluster] = []
    var clustersLoading = false
    var clustersError: String?

    // kubectl's current-context (from the default kubeconfig). klimax names each
    // cluster's context after the cluster, so this both badges the active cluster
    // in the sidebar and may hold a non-klimax context (shown in the footer).
    // Refreshed on refreshAll() and after a context switch.
    var currentKubeContext: String?

    // Cluster creation timestamps, sourced from the kube-system namespace.
    // Cached because creation time never changes for a given cluster.
    var clusterCreatedAt: [String: Date] = [:]
    private var creationTimeTask: Task<Void, Never>?

    var selection: SidebarSelection?

    // Per-selected-cluster details (rebuilt on selection change).
    var clusterDetail: ClusterDetail?

    // Time-series metrics per cluster (persists across selection changes).
    var metricsHistory: [String: MetricsHistory] = [:]
    var latestPods: [String: [PodMetric]] = [:]
    // cluster name -> pod id ("ns/name") -> sample ring buffer.
    var podHistory: [String: [String: PodMetricsHistory]] = [:]
    var metricsError: [String: String] = [:]
    private var metricsTask: Task<Void, Never>?
    private static let pollInterval: Duration = .seconds(15)

    // TCP probe results: cluster.name -> "ip:port" -> result.
    var serviceProbes: [String: [String: ProbeResult]] = [:]
    private var probeTask: Task<Void, Never>?

    struct ProbeResult: Sendable, Hashable {
        let timestamp: Date
        let isOpen: Bool
    }

    // VM CPU/memory history (host-VM-level, polled while VM is running).
    var vmHistory = VMHistory()
    private var vmPollTask: Task<Void, Never>?
    private var lastVMRaw: GuestRawSample?
    private static let vmPollInterval: Duration = .seconds(5)

    // Registry mirror disk-usage measurements, keyed by mirror name.
    var mirrorCacheSizes: [String: MirrorCacheSize] = [:]

    enum MirrorCacheSize: Sendable, Hashable {
        case measuring
        case measured(bytes: Int64, tags: Int?, repos: Int?, path: String)
        case missing(path: String)
        case storedInGuest
    }

    var inFlightAction: String?
    var actionLog: String = ""

    // Live `klimax cluster create` session. Present from the moment the user
    // confirms creation until they navigate away (or it's superseded). Drives
    // the placeholder card/row in the lists and the streaming log view.
    var creation: Creation?

    struct Creation: Sendable {
        var name: String
        var log: String = ""
        var running: Bool = true
        var failed: Bool = false
        var cancelled: Bool = false
        /// klimax's own "non-default kind node version — UNSUPPORTED" warning,
        /// surfaced verbatim when it appears in the create output.
        var versionWarning: String?
    }

    // The in-flight streaming create loop, so it can be cancelled mid-run.
    private var creationTask: Task<Void, Never>?

    /// Name of a cluster currently being provisioned that isn't in `clusters`
    /// yet — used to render a placeholder in the sidebar and overview.
    var provisioningClusterName: String? {
        guard let creation, !clusters.contains(where: { $0.name == creation.name })
        else { return nil }
        return creation.name
    }

    struct ClusterDetail: Sendable {
        var cluster: KindCluster
        var nodes: [KubeNode] = []
        var pods: [KubePod] = []
        var services: [KubeService] = []
        var metricsServerReady: Bool = false
        var serverVersion: String? = nil
        var loading: Bool = true
        var error: String? = nil
    }

    var selectedCluster: KindCluster? {
        if case .cluster(let name) = selection {
            return clusters.first { $0.name == name }
        }
        return nil
    }

    var selectedMirror: KlimaxConfig.Registries.Mirror? {
        if case .mirror(let name) = selection {
            return config?.registries?.mirrors?.first { $0.name == name }
        }
        return nil
    }

    var mirrors: [KlimaxConfig.Registries.Mirror] {
        config?.registries?.mirrors ?? []
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        await refreshAll()
        if klimaxVersion == nil {
            klimaxVersion = (try? await KlimaxCLI.version()) ?? "klimax (unknown)"
        }
        startVMPollingIfRunning()
    }

    private func startVMPollingIfRunning() {
        vmPollTask?.cancel()
        vmPollTask = nil
        guard let vm, vm.isRunning, let ssh = vm.ssh else { return }
        let guest = GuestSSH(endpoint: ssh)
        vmPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.collectVMSample(guest: guest)
                try? await Task.sleep(for: AppModel.vmPollInterval)
            }
        }
    }

    private func collectVMSample(guest: GuestSSH) async {
        guard let raw = await guest.rawSample() else { return }
        guard !Task.isCancelled else { return }
        let prev = lastVMRaw
        lastVMRaw = raw

        var cpuPercent: Double?
        if let prev {
            let totalDelta = Int64(raw.cpuTotalTicks) - Int64(prev.cpuTotalTicks)
            let idleDelta = Int64(raw.cpuIdleTicks) - Int64(prev.cpuIdleTicks)
            if totalDelta > 0 {
                let busy = Double(totalDelta - idleDelta) / Double(totalDelta)
                cpuPercent = max(0, min(100, busy * 100))
            }
        }

        let totalMiB = Double(raw.memTotalKB) / 1024.0
        let usedMiB = Double(raw.memTotalKB - raw.memAvailableKB) / 1024.0
        vmHistory.append(VMSample(
            id: UUID(),
            timestamp: raw.timestamp,
            cpuPercent: cpuPercent,
            memUsedMiB: usedMiB,
            memTotalMiB: totalMiB
        ))
    }

    /// Reload VM, config, clusters, guest probes; refresh selected-cluster detail if any.
    func refreshAll() async {
        config = InstanceDiscovery.loadConfig()
        vm = resolveSingleInstance()
        await refreshClusters()
        await refreshCurrentKubeContext()
        if let vm, vm.isRunning, let ssh = vm.ssh {
            let guest = GuestSSH(endpoint: ssh)
            async let ipTask = guest.lima0IP()
            async let statsTask = guest.stats()
            guestLima0IP = await ipTask
            guestStats = await statsTask
        } else {
            guestLima0IP = nil
            guestStats = nil
        }
        // Drop stale selection — but keep it while that cluster is still
        // provisioning (it isn't in `clusters` yet by design).
        if case .cluster(let name) = selection,
           !clusters.contains(where: { $0.name == name }),
           creation?.name != name {
            selection = nil
        }
        if case .mirror(let name) = selection, !mirrors.contains(where: { $0.name == name }) {
            selection = nil
        }
        await refreshSelection()
    }

    private func resolveSingleInstance() -> Instance? {
        let all = InstanceDiscovery.discoverInstances()
        if let declared = config?.vm.name,
           let match = all.first(where: { $0.name == declared }) {
            return match
        }
        return all.first
    }

    func refreshClusters() async {
        guard vm?.isRunning == true else {
            clusters = []
            clustersError = nil
            clusterCreatedAt = [:]
            return
        }
        clustersLoading = true
        defer { clustersLoading = false }
        do {
            clusters = try await KlimaxCLI.listClusters()
            clustersError = nil
        } catch {
            clusters = []
            clustersError = error.localizedDescription
        }
        pruneCreationTimes()
        refreshCreationTimes()
    }

    /// Read kubectl's current-context from the default kubeconfig. Nil when
    /// unset (kubectl exits non-zero) or on any error.
    func refreshCurrentKubeContext() async {
        if let result = try? await ProcessRunner.run("kubectl", ["config", "current-context"]),
           result.ok {
            let ctx = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            currentKubeContext = ctx.isEmpty ? nil : ctx
        } else {
            currentKubeContext = nil
        }
    }

    private func pruneCreationTimes() {
        let names = Set(clusters.map(\.name))
        clusterCreatedAt = clusterCreatedAt.filter { names.contains($0.key) }
    }

    /// Fetch kube-system creation timestamps for any cluster we don't yet
    /// have a cached value for. Creation time never changes, so we never
    /// re-query a cluster we've already resolved.
    private func refreshCreationTimes() {
        let missing = clusters.filter { clusterCreatedAt[$0.name] == nil }
        guard !missing.isEmpty else { return }
        creationTimeTask?.cancel()
        creationTimeTask = Task { [weak self] in
            await withTaskGroup(of: (String, Date?).self) { group in
                for c in missing {
                    let kubeconfig = c.kubeconfigPath
                    let name = c.name
                    group.addTask {
                        let date = await KubeClient(kubeconfigPath: kubeconfig)
                            .kubeSystemCreationTime()
                        return (name, date)
                    }
                }
                for await (name, date) in group {
                    guard !Task.isCancelled, let date else { continue }
                    self?.clusterCreatedAt[name] = date
                }
            }
        }
    }

    // MARK: - Selection

    func refreshSelection() async {
        // Cancel any in-flight metrics polling before changing selection state.
        metricsTask?.cancel()
        metricsTask = nil

        switch selection {
        case .cluster(let name):
            guard let cluster = clusters.first(where: { $0.name == name }) else {
                clusterDetail = nil
                return
            }
            await loadClusterDetail(for: cluster)
            startMetricsPollingIfReady(for: cluster)
        case .mirror, .none:
            clusterDetail = nil
        }
    }

    private func startMetricsPollingIfReady(for cluster: KindCluster) {
        guard clusterDetail?.cluster.name == cluster.name,
              clusterDetail?.metricsServerReady == true
        else { return }
        let client = MetricsClient(kubeconfigPath: cluster.kubeconfigPath)
        let name = cluster.name
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollMetrics(client: client, clusterName: name)
                try? await Task.sleep(for: AppModel.pollInterval)
            }
        }
    }

    private func pollMetrics(client: MetricsClient, clusterName: String) async {
        do {
            async let nodesTask = client.fetchNodes()
            async let podsTask = client.fetchPods()
            let nodes = try await nodesTask
            let pods = try await podsTask
            guard !Task.isCancelled else { return }
            let now = Date()
            let sample = ClusterMetricSample(
                timestamp: now,
                totalCPUMillicores: nodes.reduce(0) { $0 + $1.cpuMillicores },
                totalMemoryMiB: nodes.reduce(0) { $0 + $1.memoryMiB },
                perNode: nodes
            )
            var history = metricsHistory[clusterName] ?? MetricsHistory()
            history.append(sample)
            metricsHistory[clusterName] = history
            latestPods[clusterName] = pods

            // Update per-pod history; prune entries whose latest sample is
            // older than the oldest cluster sample we still keep (so pods that
            // disappear roll off in step with the cluster's time window).
            var perPod = podHistory[clusterName] ?? [:]
            for pod in pods {
                var h = perPod[pod.id] ?? PodMetricsHistory()
                h.append(pod)
                perPod[pod.id] = h
            }
            if let earliest = history.samples.first?.timestamp {
                perPod = perPod.filter {
                    ($0.value.samples.last?.timestamp ?? .distantPast) >= earliest
                }
            }
            podHistory[clusterName] = perPod
            metricsError[clusterName] = nil
        } catch {
            metricsError[clusterName] = error.localizedDescription
        }
    }

    /// Compute (and cache) disk usage for a mirror's image cache directory.
    /// The cache lives on the host by default (~/.klimax/registry-cache/<name>);
    /// when configured to live in the guest we surface that state without measuring.
    func measureMirrorCache(_ mirror: KlimaxConfig.Registries.Mirror) async {
        let storage = config?.registries?.cacheStorage ?? "host"
        if storage == "guest" {
            mirrorCacheSizes[mirror.name] = .storedInGuest
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home
            .appendingPathComponent(".klimax")
            .appendingPathComponent("registry-cache")
            .appendingPathComponent(mirror.name)
            .path
        mirrorCacheSizes[mirror.name] = .measuring
        async let sizeTask = DirectorySize.measure(path: path)
        async let countsTask = RegistryCacheInspector.count(path: path)
        let bytes = await sizeTask
        let counts = await countsTask
        if let bytes {
            mirrorCacheSizes[mirror.name] = .measured(
                bytes: bytes,
                tags: counts?.tags,
                repos: counts?.repos,
                path: path
            )
        } else {
            mirrorCacheSizes[mirror.name] = .missing(path: path)
        }
    }

    /// Probe TCP reachability for every (LB IP, TCP port) on the cluster's
    /// LoadBalancer services. Runs in the background; cancels any previous batch.
    func probeLoadBalancers(for cluster: KindCluster) {
        guard let detail = clusterDetail, detail.cluster.name == cluster.name else { return }
        let lbs = detail.services.filter(\.isLoadBalancer)
        var targets: [(ip: String, port: Int)] = []
        for svc in lbs {
            let ips = svc.externalIPs
            let ports = (svc.spec.ports ?? []).filter { $0.protocolValue.uppercased() == "TCP" }
            for ip in ips {
                for port in ports {
                    targets.append((ip, port.port))
                }
            }
        }
        guard !targets.isEmpty else {
            serviceProbes[cluster.name] = [:]
            return
        }

        probeTask?.cancel()
        let name = cluster.name
        probeTask = Task { [weak self] in
            let results = await withTaskGroup(of: (String, ProbeResult).self) { group -> [String: ProbeResult] in
                for target in targets {
                    group.addTask {
                        let ok = await TCPProbe.probe(host: target.ip, port: target.port)
                        return ("\(target.ip):\(target.port)",
                                ProbeResult(timestamp: Date(), isOpen: ok))
                    }
                }
                var bucket: [String: ProbeResult] = [:]
                for await pair in group {
                    bucket[pair.0] = pair.1
                }
                return bucket
            }
            guard !Task.isCancelled else { return }
            self?.serviceProbes[name] = results
        }
    }

    /// Called externally when the user toggles metrics-server install/uninstall.
    /// Restart or stop polling based on current readiness.
    func refreshMetricsPolling() {
        if case .cluster(let name) = selection,
           let cluster = clusters.first(where: { $0.name == name }) {
            startMetricsPollingIfReady(for: cluster)
        } else {
            metricsTask?.cancel()
            metricsTask = nil
        }
    }

    func loadClusterDetail(for cluster: KindCluster) async {
        clusterDetail = ClusterDetail(cluster: cluster, loading: true)
        let kube = KubeClient(kubeconfigPath: cluster.kubeconfigPath)
        do {
            async let nodesTask = kube.listNodes()
            async let podsTask = kube.listPods()
            async let servicesTask = kube.listServices()
            async let metricsTask = kube.metricsServerReady()
            async let versionTask = kube.clusterVersion()
            let nodes = try await nodesTask
            let pods = try await podsTask
            let services = try await servicesTask
            let metricsReady = await metricsTask
            let version = await versionTask
            clusterDetail = ClusterDetail(
                cluster: cluster,
                nodes: nodes,
                pods: pods,
                services: services,
                metricsServerReady: metricsReady,
                serverVersion: version,
                loading: false,
                error: nil
            )
            probeLoadBalancers(for: cluster)
        } catch {
            clusterDetail = ClusterDetail(
                cluster: cluster,
                loading: false,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Actions

    func startVM() async {
        await runAction("Starting VM") { try await KlimaxCLI.up() }
    }

    func stopVM() async {
        await runAction("Stopping VM") { try await KlimaxCLI.down() }
    }

    func createCluster(named name: String) async {
        guard inFlightAction == nil, creation?.running != true else { return }
        let label = "Creating cluster \(name)"
        inFlightAction = label
        actionLog = ""
        creation = Creation(name: name)
        // Surface the placeholder and its live log immediately.
        selection = .cluster(name: name)

        // Run the stream in a cancellable task; cancelling it tears down the
        // AsyncStream, which terminates the underlying `klimax cluster create`.
        let streamTask = Task { @MainActor in
            for await event in ProcessRunner.stream(
                KlimaxCLI.executable, ["cluster", "create", name]
            ) {
                switch event {
                case .output(let text):
                    creation?.log = text
                    if creation?.versionWarning == nil,
                       let warning = Self.detectVersionWarning(in: text) {
                        creation?.versionWarning = warning
                    }
                case .finished(let result):
                    creation?.failed = !result.ok
                    actionLog = combinedLog(label: label, result: result)
                }
            }
        }
        creationTask = streamTask
        await streamTask.value
        let wasCancelled = streamTask.isCancelled
        creationTask = nil

        if wasCancelled {
            creation?.cancelled = true
            creation?.failed = true
            creation?.log += "\n── Cancelled — cleaning up partial cluster ──\n"
            if let del = try? await KlimaxCLI.deleteCluster(name: name) {
                creation?.log += combinedLog(label: "Deleting cluster \(name)", result: del)
            }
        }

        creation?.running = false
        inFlightAction = nil
        await refreshAll()
        startVMPollingIfRunning()
        // On success the real cluster is now in the list; drop the session so
        // ClusterDetailView takes over. On failure/cancel keep it so the log stays.
        if creation?.failed == false, clusters.contains(where: { $0.name == name }) {
            creation = nil
        }
    }

    /// Cancel the in-flight cluster creation, if any. The create process is
    /// terminated and the partial cluster is cleaned up (see `createCluster`).
    func cancelCreation() {
        creationTask?.cancel()
    }

    /// Extract klimax's mismatch warning line, if present. klimax logs (to
    /// stderr) `level=WARN msg="Using a non-default kind node version — …"`
    /// with `requested`/`recommended` fields whenever the configured
    /// nodeVersion differs from the one its bundled kind CLI is validated
    /// against. We surface that verbatim rather than hardcode the default.
    static func detectVersionWarning(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard lower.contains("non-default kind node version")
                    || lower.contains("unsupported") && lower.contains("node") else { continue }
            return line.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    func deleteCluster(named name: String) async {
        await runAction("Deleting cluster \(name)") {
            try await KlimaxCLI.deleteCluster(name: name)
        }
        if case .cluster(let sel) = selection, sel == name {
            selection = nil
        }
    }

    /// Set kubectl's current-context (in the default kubeconfig) to this
    /// cluster. klimax merges each cluster into ~/.kube/config under a context
    /// named after the cluster, so `use-context <name>` targets it directly.
    func useContext(for cluster: KindCluster) async {
        await runAction("Switching kubectl context to \(cluster.name)") {
            try await ProcessRunner.run("kubectl", ["config", "use-context", cluster.name])
        }
    }

    func installMetricsServer(for cluster: KindCluster) async {
        await runAction("Installing metrics-server on \(cluster.name)") {
            try await Helm(kubeconfigPath: cluster.kubeconfigPath).installMetricsServer()
        }
    }

    func uninstallMetricsServer(for cluster: KindCluster) async {
        await runAction("Uninstalling metrics-server on \(cluster.name)") {
            try await Helm(kubeconfigPath: cluster.kubeconfigPath).uninstallMetricsServer()
        }
    }

    private func runAction(_ label: String, _ work: () async throws -> ProcessResult) async {
        inFlightAction = label
        actionLog = ""
        creation = nil  // a new action supersedes any finished create session
        defer { inFlightAction = nil }
        do {
            let result = try await work()
            actionLog = combinedLog(label: label, result: result)
        } catch {
            actionLog = "\(label) failed: \(error.localizedDescription)"
        }
        await refreshAll()
        startVMPollingIfRunning()
    }

    private func combinedLog(label: String, result: ProcessResult) -> String {
        var out = "\(label) — exit \(result.exitCode)\n"
        if !result.stdout.isEmpty { out += "── stdout ──\n\(result.stdout)\n" }
        if !result.stderr.isEmpty { out += "── stderr ──\n\(result.stderr)\n" }
        return out
    }
}
