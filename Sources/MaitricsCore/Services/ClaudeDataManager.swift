import Foundation

@Observable
public final class ClaudeDataManager {
    public private(set) var statsCache: StatsCache?
    public private(set) var recentSessions: [RecentSession] = []
    public private(set) var usageData: UsageData?
    public private(set) var lastRefresh: Date?
    public private(set) var isLoading = false
    public private(set) var error: String?

    private let settings: AppSettings
    private var sessionTokenCache: [String: (mtime: Date, usage: SessionTokenUsage)] = [:]

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

        Task.detached { [weak self] in
            guard let self else { return }
            let settings = self.settings

            // Parse stats cache
            var newStatsCache: StatsCache?
            var newError: String?
            do {
                newStatsCache = try StatsCacheParser.parse(fileURL: settings.statsCachePath)
            } catch {
                if FileManager.default.fileExists(atPath: settings.statsCachePath.path) {
                    newError = "Failed to parse stats: \(error.localizedDescription)"
                }
            }

            // Discover sessions
            var newSessions: [RecentSession] = []
            if let discovered = try? SessionDiscovery.discoverSessions(claudeProjectsDir: settings.projectsPath) {
                let topSessions = Array(discovered.prefix(5))
                newSessions = topSessions.map { session in
                    let tokenUsage = self.cachedTokenUsage(for: session, settings: settings)
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
            }

            // Fetch API usage data
            let newUsageData = await UsageAPIClient.fetchUsage()

            let finalStats = newStatsCache
            let finalSessions = newSessions
            let finalError = newError
            let finalUsage = newUsageData
            await MainActor.run {
                self.statsCache = finalStats
                self.recentSessions = finalSessions
                if let finalUsage { self.usageData = finalUsage }
                if let finalError { self.error = finalError }
                self.lastRefresh = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Helpers

    /// Cache session JSONL parsing — only re-parse when file mtime changes
    private func cachedTokenUsage(for session: DiscoveredSession, settings: AppSettings) -> SessionTokenUsage? {
        guard let path = session.jsonlPath else { return nil }
        let fileURL = URL(fileURLWithPath: path)

        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date.distantPast

        if let cached = sessionTokenCache[session.sessionId], cached.mtime == mtime {
            return cached.usage
        }

        guard let usage = try? SessionParser.parseTokenUsage(fileURL: fileURL) else { return nil }
        sessionTokenCache[session.sessionId] = (mtime: mtime, usage: usage)
        return usage
    }

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
