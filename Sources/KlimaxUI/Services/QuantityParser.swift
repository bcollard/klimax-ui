import Foundation

/// Parses Kubernetes resource.Quantity strings — see
/// https://github.com/kubernetes/apimachinery/blob/master/pkg/api/resource/quantity.go
/// We only need the suffixes the kubelet/metrics-server actually emits.
enum QuantityParser {
    /// CPU as millicores. Inputs include nanocores ("93642001n"), microcores ("12u"),
    /// millicores ("123m"), and plain cores ("0.5", "2"). Returns nil on parse failure.
    static func cpuMillicores(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        // Strip suffix letters from the right.
        let (numericPart, suffix) = splitNumericAndSuffix(s)
        guard let value = Double(numericPart) else { return nil }
        switch suffix {
        case "n":  return value / 1_000_000           // nanocores → millicores
        case "u":  return value / 1_000               // microcores → millicores
        case "m":  return value                       // already millicores
        case "":   return value * 1_000               // cores → millicores
        case "k":  return value * 1_000_000           // kilocores (rare)
        default:   return nil
        }
    }

    /// Memory as MiB. Inputs include binary ("256Ki", "512Mi", "2Gi") and
    /// decimal ("123M", "1G"), and plain bytes ("12345"). Returns nil on parse failure.
    static func memoryMiB(_ s: String) -> Double? {
        guard !s.isEmpty else { return nil }
        let (numericPart, suffix) = splitNumericAndSuffix(s)
        guard let value = Double(numericPart) else { return nil }
        let bytes: Double
        switch suffix {
        case "":   bytes = value
        case "k":  bytes = value * 1_000
        case "M":  bytes = value * 1_000_000
        case "G":  bytes = value * 1_000_000_000
        case "T":  bytes = value * 1_000_000_000_000
        case "Ki": bytes = value * 1024
        case "Mi": bytes = value * 1024 * 1024
        case "Gi": bytes = value * 1024 * 1024 * 1024
        case "Ti": bytes = value * 1024 * 1024 * 1024 * 1024
        default:   return nil
        }
        return bytes / 1024.0 / 1024.0
    }

    /// Split into the leading numeric part and the trailing unit suffix.
    /// Allows a leading sign and a single decimal point.
    private static func splitNumericAndSuffix(_ s: String) -> (String, String) {
        var idx = s.startIndex
        let chars = Array(s)
        var seenDot = false
        var i = 0
        if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { i += 1 }
            else if c == "." && !seenDot { seenDot = true; i += 1 }
            else { break }
        }
        idx = s.index(s.startIndex, offsetBy: i)
        return (String(s[s.startIndex..<idx]), String(s[idx...]))
    }
}
