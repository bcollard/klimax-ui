import Foundation
import Yams

enum InstanceDiscovery {
    /// Reserved subdirectory names under ~/.klimax that are not VM instances.
    private static let reservedDirs: Set<String> = ["_config", "registry-cache", "share"]

    static func klimaxRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".klimax", isDirectory: true)
    }

    static func configFile() -> URL {
        klimaxRoot().appendingPathComponent("config.yaml")
    }

    /// Load the user-level klimax config, if it exists.
    static func loadConfig() -> KlimaxConfig? {
        let url = configFile()
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return try? YAMLDecoder().decode(KlimaxConfig.self, from: raw)
    }

    /// Enumerate instances by scanning ~/.klimax/ for instance directories.
    static func discoverInstances() -> [Instance] {
        let root = klimaxRoot()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }

        return entries.compactMap { url -> Instance? in
            let name = url.lastPathComponent
            if reservedDirs.contains(name) || name.hasPrefix(".") { return nil }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return buildInstance(name: name, dir: url)
        }
        .sorted { $0.name < $1.name }
    }

    private static func buildInstance(name: String, dir: URL) -> Instance {
        let runtime = readRuntime(dir: dir)
        let sshPath = dir.appendingPathComponent("ssh.config").path
        let ssh = (try? SSHConfigParser.parse(at: sshPath)) ?? nil
        let lima = readLimaConfig(dir: dir)
        return Instance(name: name, dir: dir, runtime: runtime, ssh: ssh, lima: lima)
    }

    private static func readRuntime(dir: URL) -> Instance.Runtime {
        let vzPID = readPID(dir.appendingPathComponent("vz.pid"))
        let haPID = readPID(dir.appendingPathComponent("ha.pid"))
        guard let vz = vzPID else { return .stopped }
        // A stale pid file can outlive the process — verify it's actually running.
        if ProcessRunner.isAlive(pid: vz) {
            return .running(vzPID: vz, haPID: haPID)
        }
        return .stopped
    }

    private static func readPID(_ url: URL) -> Int32? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func readLimaConfig(dir: URL) -> Instance.LimaConfig? {
        let url = dir.appendingPathComponent("lima.yaml")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // lima.yaml is a full Lima template — we only care about a few top-level scalars.
        struct LimaTop: Decodable {
            let cpus: Int?
            let memory: String?
            let disk: String?
            let vmType: String?
        }
        guard let top = try? YAMLDecoder().decode(LimaTop.self, from: raw) else { return nil }
        return Instance.LimaConfig(
            cpus: top.cpus,
            memory: top.memory,
            disk: top.disk,
            vmType: top.vmType
        )
    }
}
