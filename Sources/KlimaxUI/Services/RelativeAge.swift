import Foundation

/// Compact "Xd Yh Zm" age formatter for cluster lifetime display.
enum RelativeAge {
    static func format(since start: Date, now: Date = Date()) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        if total < 60 { return "<1m" }
        let minutes = (total / 60) % 60
        let hours = (total / 3600) % 24
        let days = total / 86400
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
