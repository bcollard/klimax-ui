import Foundation

enum SSHConfigParser {
    static func parse(at path: String) throws -> SSHEndpoint? {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        var hostAlias: String?
        var fields: [String: String] = [:]

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = unquote(String(parts[1]).trimmingCharacters(in: .whitespaces))

            if key == "host" {
                hostAlias = value
                continue
            }
            fields[key] = value
        }

        guard let alias = hostAlias,
              let host = fields["hostname"],
              let portStr = fields["port"],
              let port = Int(portStr),
              let user = fields["user"],
              let identity = fields["identityfile"]
        else { return nil }

        return SSHEndpoint(
            hostAlias: alias,
            configPath: path,
            hostname: host,
            port: port,
            user: user,
            identityFile: identity,
            controlPath: fields["controlpath"]
        )
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, s.first == "\"", s.last == "\"" else { return s }
        return String(s.dropFirst().dropLast())
    }
}
