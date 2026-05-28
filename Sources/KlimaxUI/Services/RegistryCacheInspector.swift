import Foundation

/// Counts images cached by a Docker registry storage tree. Relies on the v2
/// filesystem layout: each tag has a `_manifests/tags/<tag>/current/link` file
/// and each repository has exactly one `_manifests` directory.
enum RegistryCacheInspector {
    struct Counts: Sendable, Hashable {
        let tags: Int
        let repos: Int
    }

    static func count(path: String) async -> Counts? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else { return nil }

        async let tagsTask = countMatches(in: path, predicate: ["-path", "*/_manifests/tags/*/current/link", "-type", "f"])
        async let reposTask = countMatches(in: path, predicate: ["-type", "d", "-name", "_manifests"])
        let tags = await tagsTask
        let repos = await reposTask
        guard let tags, let repos else { return nil }
        return Counts(tags: tags, repos: repos)
    }

    /// Run `find <path> <predicate...>` and count output lines.
    private static func countMatches(in path: String, predicate: [String]) async -> Int? {
        let args = [path] + predicate
        guard let result = try? await ProcessRunner.run("find", args), result.ok else {
            return nil
        }
        // find prints one match per line; trailing newline produces an empty final element.
        return result.stdout.split(whereSeparator: \.isNewline).count
    }
}
