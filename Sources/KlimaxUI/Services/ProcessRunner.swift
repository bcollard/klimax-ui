import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
}

enum ProcessError: Error, LocalizedError {
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return "Failed to launch: \(m)"
        case .nonZeroExit(let c, let s): return "Exit \(c): \(s)"
        }
    }
}

enum ProcessRunner {
    /// Run a command to completion and capture stdout/stderr.
    static func run(
        _ executable: String,
        _ args: [String],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
            let process = Process()
            process.executableURL = resolve(executable)
            process.arguments = args
            if let environment {
                var env = ProcessInfo.processInfo.environment
                for (k, v) in environment { env[k] = v }
                process.environment = env
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let outBox = DataBox()
            let errBox = DataBox()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    outBox.append(chunk)
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    errBox.append(chunk)
                }
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // Drain any remaining data.
                let leftoverOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let leftoverErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                outBox.append(leftoverOut)
                errBox.append(leftoverErr)
                cont.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: outBox.string,
                    stderr: errBox.string
                ))
            }

            do {
                try process.run()
            } catch {
                cont.resume(throwing: ProcessError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Check whether a process with the given PID is currently alive.
    static func isAlive(pid: Int32) -> Bool {
        // kill with signal 0 just checks for existence/permission.
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private static func resolve(_ executable: String) -> URL {
        if executable.hasPrefix("/") {
            return URL(fileURLWithPath: executable)
        }
        // Search PATH manually so we don't rely on /usr/bin/env on every call.
        let candidates = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map { String($0) }
        // Always include common Homebrew and system paths since GUI apps inherit
        // a stripped PATH.
        let extras = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        for path in candidates + extras {
            let candidate = URL(fileURLWithPath: path).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        // Fallback — will likely fail at run-time, surfaced to caller.
        return URL(fileURLWithPath: "/usr/bin/env")
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }
    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
