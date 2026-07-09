import Foundation

struct KlimaxConfig: Sendable, Hashable, Decodable {
    let vm: VM
    let network: Network?
    let kind: Kind?
    let registries: Registries?

    struct VM: Sendable, Hashable, Decodable {
        let name: String
        let cpus: Int?
        let memory: String?
        let disk: String?
        let rosetta: Bool?
    }

    struct Network: Sendable, Hashable, Decodable {
        let kindBridgeCIDR: String?
        let disablePortMirroring: Bool?
    }

    struct Kind: Sendable, Hashable, Decodable {
        let nodeVersion: String?
        let metalLBVersion: String?
    }

    struct Registries: Sendable, Hashable, Decodable {
        let mirrors: [Mirror]?
        let cacheStorage: String?

        struct Mirror: Sendable, Hashable, Decodable {
            let name: String
            let port: Int
            let remoteURL: String
        }
    }
}
