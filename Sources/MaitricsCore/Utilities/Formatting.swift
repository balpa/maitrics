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

    public static func shortModelName(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        if lower.contains("opus") { return "Opus" }
        if lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("haiku") { return "Haiku" }
        return modelId
    }
}
