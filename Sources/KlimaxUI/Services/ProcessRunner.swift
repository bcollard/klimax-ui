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

/// Events emitted while streaming a long-running process.
/// `.output` carries the full combined stdout+stderr text captured so far
/// (replace semantics — decoding the whole buffer each time sidesteps UTF-8
/// multibyte splits at chunk boundaries, which kind's emoji output triggers).
enum ProcessEvent: Sendable {
    case output(String)
    case finished(ProcessResult)
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

    /// Run a command while streaming its combined stdout/stderr as it arrives.
    /// Yields `.output` snapshots (full text so far) then a terminal `.finished`.
    static func stream(
        _ executable: String,
        _ args: [String],
        environment: [String: String]? = nil
    ) -> AsyncStream<ProcessEvent> {
        AsyncStream { continuation in
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

            let outBox = DataBox()   // stdout only, for the final result
            let errBox = DataBox()   // stderr only, for the final result
            let combined = DataBox()  // interleaved, for the live view

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil; return }
                outBox.append(chunk)
                combined.append(chunk)
                continuation.yield(.output(combined.string))
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil; return }
                errBox.append(chunk)
                combined.append(chunk)
                continuation.yield(.output(combined.string))
            }

            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let leftoverOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let leftoverErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                if !leftoverOut.isEmpty { outBox.append(leftoverOut); combined.append(leftoverOut) }
                if !leftoverErr.isEmpty { errBox.append(leftoverErr); combined.append(leftoverErr) }
                continuation.yield(.output(combined.string))
                continuation.yield(.finished(ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: outBox.string,
                    stderr: errBox.string
                )))
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.finished(ProcessResult(
                    exitCode: -1,
                    stdout: "",
                    stderr: "Failed to launch: \(error.localizedDescription)"
                )))
                continuation.finish()
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
        // Lossy decode of the *whole* buffer: a multibyte char split across a
        // chunk boundary shows a transient replacement char and self-corrects
        // once the trailing bytes arrive, rather than nil-ing the entire log.
        return String(decoding: data, as: UTF8.self)
    }
}
