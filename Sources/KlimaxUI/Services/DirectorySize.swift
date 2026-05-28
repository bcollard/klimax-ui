import Foundation

/// Computes on-disk size of a directory by shelling out to `du -sk`.
/// `-k` forces 1024-byte blocks; the first token of stdout is KiB.
/// We use the system `du` rather than a Foundation walk because caches with
/// tens of thousands of small layer files are dramatically faster with `du`.
enum DirectorySize {
    /// Returns size in bytes, or nil if the path doesn't exist or `du` fails.
    static func measure(path: String) async -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        guard let result = try? await ProcessRunner.run("du", ["-sk", path]), result.ok else {
            return nil
        }
        // Output: "1234567\t/path/to/dir"
        let first = result.stdout.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard let kib = Int64(first) else { return nil }
        return kib * 1024
    }
}
