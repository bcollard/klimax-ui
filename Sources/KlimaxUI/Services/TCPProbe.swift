import Foundation
import Network

/// One-shot TCP reachability probe via Network framework. Used to confirm a
/// LoadBalancer endpoint is actually accepting connections from this host —
/// stronger than checking the IP falls in a configured CIDR.
enum TCPProbe {
    /// Try to establish a TCP connection to host:port. Returns true on .ready,
    /// false on .failed/.cancelled/.waiting or timeout.
    /// `.waiting` indicates the kernel can't even attempt the path (no route,
    /// peer unreachable) — we treat that as failure rather than waiting out
    /// the full timeout window.
    static func probe(host: String, port: Int, timeout: TimeInterval = 1.5) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: .tcp
            )
            let once = OnceFlag()
            let queue = DispatchQueue(label: "tcp-probe-\(host):\(port)")

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.tryFlip() {
                        conn.cancel()
                        cont.resume(returning: true)
                    }
                case .failed, .cancelled, .waiting:
                    if once.tryFlip() {
                        conn.cancel()
                        cont.resume(returning: false)
                    }
                default:
                    break
                }
            }

            conn.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                if once.tryFlip() {
                    conn.cancel()
                    cont.resume(returning: false)
                }
            }
        }
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func tryFlip() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
