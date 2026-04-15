import Foundation

public enum Formatting {
    public static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000.0
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        } else if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return k >= 10 ? String(format: "%.0fk", k) : String(format: "%.1fk", k)
        }
        return "\(count)"
    }

    public static func cost(_ amount: Double) -> String {
        if amount >= 100 { return String(format: "$%.0f", amount) }
        else if amount >= 0.01 { return String(format: "$%.2f", amount) }
        else if amount > 0 { return "<$0.01" }
        return "$0.00"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    public static func timeAgo(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// More precise "resets in" format: "1h 23m", "45m", "5d 3h"
    public static func timeUntil(_ date: Date) -> String {
        let seconds = date.timeIntervalSince(Date())
        guard seconds > 0 else { return "now" }

        let totalMinutes = Int(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return remainingHours > 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
        } else if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    public static func shortModelName(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        // Skip synthetic/internal model entries
        if lower.contains("synthetic") || lower.hasPrefix("<") { return "" }
        return modelId
    }
}
