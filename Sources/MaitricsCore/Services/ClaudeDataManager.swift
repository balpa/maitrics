import Foundation

@Observable
public final class ClaudeDataManager {
    public private(set) var statsCache: StatsCache?
    public private(set) var recentSessions: [RecentSession] = []
    public private(set) var lastRefresh: Date?
    public private(set) var isLoading = false
    public private(set) var error: String?

    private let settings: AppSettings

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    // MARK: - Computed Properties

    public var todayTokens: Int { todayModelTokens.values.reduce(0, +) }

    public var todayModelTokens: [String: Int] {
        guard let statsCache else { return [:] }
        let todayStr = Self.dateString(for: Date())
        return statsCache.dailyModelTokens.first { $0.date == todayStr }?.tokensByModel ?? [:]
    }

    public var todayActivity: DailyActivity? {
        guard let statsCache else { return nil }
        let todayStr = Self.dateString(for: Date())
        return statsCache.dailyActivity.first { $0.date == todayStr }
    }

    public var todayEstimatedCost: Double {
        guard let statsCache else { return 0 }
        return estimateDailyCost(dailyTokens: todayModelTokens, modelUsage: statsCache.modelUsage)
    }

    public var modelBreakdown: [(name: String, tokens: Int, color: String)] {
        let grouped = groupByFamily(todayModelTokens)
        return grouped.sorted { $0.value > $1.value }.map { family, tokens in
            let color: String
            switch family {
            case "Opus": color = "orange"
            case "Haiku": color = "purple"
            default: color = "blue"
            }
            return (name: family, tokens: tokens, color: color)
        }
    }

    public func dailyTotals(days: Int?) -> [(date: Date, tokens: Int)] {
        guard let statsCache else { return [] }
        let formatter = Self.dateFormatter
        var results: [(date: Date, tokens: Int)] = statsCache.dailyModelTokens.compactMap { day in
            guard let date = formatter.date(from: day.date) else { return nil }
            let total = day.tokensByModel.values.reduce(0, +)
            return (date: date, tokens: total)
        }
        results.sort { $0.date < $1.date }
        if let days {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
            results = results.filter { $0.date >= cutoff }
        }
        return results
    }

    public var iconThresholdLevel: ThresholdLevel {
        let tokens = todayTokens
        if tokens >= settings.thresholdYellow { return .red }
        if tokens >= settings.thresholdGreen { return .yellow }
        return .green
    }

    // MARK: - Refresh

    public func refresh() {
        isLoading = true
        error = nil

        do {
            statsCache = try StatsCacheParser.parse(fileURL: settings.statsCachePath)
        } catch {
            if FileManager.default.fileExists(atPath: settings.statsCachePath.path) {
                self.error = "Failed to parse stats: \(error.localizedDescription)"
            }
        }

        do {
            let discovered = try SessionDiscovery.discoverSessions(claudeProjectsDir: settings.projectsPath)
            let topSessions = Array(discovered.prefix(5))
            recentSessions = topSessions.map { session in
                var tokenUsage: SessionTokenUsage?
                if let path = session.jsonlPath {
                    tokenUsage = try? SessionParser.parseTokenUsage(fileURL: URL(fileURLWithPath: path))
                }
                let cost = tokenUsage.map { CostCalculator.cost(for: $0, customPricing: settings.customPricing) } ?? 0
                let totalTokens = tokenUsage?.totalTokens ?? 0
                return RecentSession(
                    sessionId: session.sessionId,
                    firstPrompt: session.firstPrompt,
                    projectName: session.projectName,
                    gitBranch: session.gitBranch,
                    modified: session.modified,
                    totalTokens: totalTokens,
                    estimatedCost: cost
                )
            }
        } catch {
            // Non-fatal
        }

        lastRefresh = Date()
        isLoading = false
    }

    // MARK: - Helpers

    private func estimateDailyCost(dailyTokens: [String: Int], modelUsage: [String: ModelUsage]) -> Double {
        dailyTokens.reduce(0.0) { total, pair in
            let (modelId, dailyTotal) = pair
            guard dailyTotal > 0 else { return total }
            if let usage = modelUsage[modelId], usage.totalTokens > 0 {
                let scale = Double(dailyTotal) / Double(usage.totalTokens)
                return total + CostCalculator.cost(for: usage, model: modelId, customPricing: settings.customPricing) * scale
            }
            let pricing = CostCalculator.pricing(for: modelId, customPricing: settings.customPricing)
            return total + Double(dailyTotal) / 1_000_000.0 * pricing.outputPer1M
        }
    }

    private func groupByFamily(_ tokensByModel: [String: Int]) -> [String: Int] {
        var grouped: [String: Int] = [:]
        for (modelId, tokens) in tokensByModel {
            let family = Formatting.shortModelName(modelId)
            grouped[family, default: 0] += tokens
        }
        return grouped
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

public enum ThresholdLevel: Sendable {
    case green, yellow, red
}

public struct RecentSession: Identifiable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let firstPrompt: String
    public let projectName: String
    public let gitBranch: String?
    public let modified: Date
    public let totalTokens: Int
    public let estimatedCost: Double
}
