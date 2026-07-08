import Foundation

/// Executes commands in the guest VM by shelling out to `ssh -F <instance>/ssh.config`.
/// Reuses klimax's existing ControlMaster socket so calls are cheap and require no
/// extra credentials beyond what klimax already wrote to disk.
struct GuestSSH: Sendable {
    let endpoint: SSHEndpoint

    enum GuestError: Error, LocalizedError {
        case command(Int32, String)
        var errorDescription: String? {
            if case .command(let c, let s) = self { return "ssh exited \(c): \(s)" }
            return nil
        }
    }

    /// Run a one-shot command and return stdout. Throws on non-zero exit.
    func run(_ command: String, timeout: TimeInterval = 10) async throws -> String {
        // Use BatchMode + ConnectTimeout to fail fast if the VM is down.
        let args = [
            "-F", endpoint.configPath,
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=\(Int(timeout))",
            endpoint.hostAlias,
            command,
        ]
        let result = try await ProcessRunner.run("ssh", args)
        guard result.ok else {
            throw GuestError.command(result.exitCode, result.stderr)
        }
        return result.stdout
    }

    /// Probe lima0 IPv4 address. Returns nil if the interface isn't up or VM isn't reachable.
    func lima0IP() async -> String? {
        guard let out = try? await run(
            "ip -4 -o addr show lima0 2>/dev/null | awk '{print $4}' | cut -d/ -f1"
        ) else { return nil }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Snapshot of basic guest stats. All fields are best-effort.
    struct GuestStats: Sendable, Hashable {
        let uptime: String?
        let loadAvg: String?
        let memTotalKB: Int?
        let memAvailableKB: Int?
        let kernel: String?
    }

    /// Single-shot reading of CPU counters and memory totals for time-series
    /// graphing. One SSH round-trip; rides the existing ControlMaster socket.
    func rawSample() async -> GuestRawSample? {
        guard let out = try? await run(
            "head -1 /proc/stat; echo '---'; head -3 /proc/meminfo; echo '---'; cat /proc/loadavg"
        ) else { return nil }
        let parts = out.components(separatedBy: "---")
        guard parts.count >= 2 else { return nil }
        guard let (total, idle) = parseProcStat(parts[0]) else { return nil }
        let (totalKB, availKB) = parseMemInfo(parts[1])
        guard let totalKB, let availKB else { return nil }
        let loadAvg = parts.count >= 3
            ? parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        return GuestRawSample(
            timestamp: Date(),
            cpuTotalTicks: total,
            cpuIdleTicks: idle,
            memTotalKB: totalKB,
            memAvailableKB: availKB,
            loadAvg: (loadAvg?.isEmpty ?? true) ? nil : loadAvg
        )
    }

    /// Parse `/proc/stat`'s first line: "cpu  user nice system idle iowait …".
    /// Returns (totalTicks, idleTicks) where idle includes iowait per the
    /// convention used by `top`, `mpstat`, etc.
    private func parseProcStat(_ block: String) -> (UInt64, UInt64)? {
        for line in block.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "cpu", fields.count >= 6 else { continue }
            let nums = fields.dropFirst().compactMap { UInt64($0) }
            guard nums.count >= 5 else { return nil }
            let total = nums.reduce(0, +)
            let idle = nums[3] + nums[4]  // idle + iowait
            return (total, idle)
        }
        return nil
    }

    private func parseMemInfo(_ block: String) -> (Int?, Int?) {
        var total: Int?
        var avail: Int?
        for line in block.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("MemTotal:") { total = parseKB(String(line)) }
            else if line.hasPrefix("MemAvailable:") { avail = parseKB(String(line)) }
        }
        return (total, avail)
    }

    func stats() async -> GuestStats {
        async let uptime = try? await run("uptime -p").trimmingCharacters(in: .whitespacesAndNewlines)
        async let loadAvg = try? await run("cat /proc/loadavg").trimmingCharacters(in: .whitespacesAndNewlines)
        async let meminfo = try? await run("cat /proc/meminfo")
        async let kernel = try? await run("uname -r").trimmingCharacters(in: .whitespacesAndNewlines)

        let memText = await meminfo
        var memTotal: Int?
        var memAvail: Int?
        if let memText {
            for line in memText.split(separator: "\n") {
                if line.hasPrefix("MemTotal:") { memTotal = parseKB(String(line)) }
                else if line.hasPrefix("MemAvailable:") { memAvail = parseKB(String(line)) }
            }
        }
        return GuestStats(
            uptime: await uptime,
            loadAvg: await loadAvg,
            memTotalKB: memTotal,
            memAvailableKB: memAvail,
            kernel: await kernel
        )
    }

    private func parseKB(_ line: String) -> Int? {
        // "MemTotal:       20480000 kB"
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }
}
