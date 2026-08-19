import Foundation

@Observable
public final class ClaudeDataManager {
    public private(set) var statsCache: StatsCache?
    public private(set) var recentSessions: [RecentSession] = []
    public private(set) var liveDailyTokens: [String: [String: Int]] = [:] // date -> model -> tokens
    public private(set) var usageData: UsageData?
    public private(set) var profileData: ProfileData?
    public private(set) var lastRefresh: Date?
    public private(set) var isLoading = false
    public private(set) var error: String?
    public var hasToken: Bool { UsageAPIClient.hasToken }
    public var apiError: UsageAPIClient.APIError? { UsageAPIClient.lastError }

    private let settings: AppSettings
    private let usageIndex: JSONLUsageIndex

    /// Guards against stacking refreshes: the file watcher, the popover and the
    /// initial load can all fire at once, and each refresh walks the session
    /// transcripts. Overlapping runs would multiply that work for nothing — but a
    /// request that arrives mid-run must not be *lost* either, or the newest
    /// stats-cache contents stay hidden until some later unrelated write, so one
    /// follow-up run is remembered and issued when the current one finishes.
    private let refreshLock = NSLock()
    private var isRefreshing = false
    private var refreshPending = false

    public init(settings: AppSettings = AppSettings(), usageIndex: JSONLUsageIndex = JSONLUsageIndex()) {
        self.settings = settings
        self.usageIndex = usageIndex
        PricingUpdater.loadCachedPricing()
    }

    // MARK: - Computed Properties

    public var todayTokens: Int {
        let todayStr = Self.dateString(for: Date())
        // Prefer live data, fall back to stats cache
        if let live = liveDailyTokens[todayStr] {
            return live.values.reduce(0, +)
        }
        return todayModelTokens.values.reduce(0, +)
    }

    public var todayModelTokens: [String: Int] {
        let todayStr = Self.dateString(for: Date())
        if let live = liveDailyTokens[todayStr] {
            return live
        }
        guard let statsCache else { return [:] }
        return statsCache.dailyModelTokens.first { $0.date == todayStr }?.tokensByModel ?? [:]
    }

    public var todaySessionCount: Int {
        let todayStr = Self.dateString(for: Date())
        // Check stats cache first
        if let statsCache,
           let activity = statsCache.dailyActivity.first(where: { $0.date == todayStr }) {
            return activity.sessionCount
        }
        // Fall back to counting recent sessions modified today
        let todayStart = Calendar.current.startOfDay(for: Date())
        return recentSessions.filter { $0.modified >= todayStart }.count
    }

    public var todayEstimatedCost: Double {
        guard let statsCache else { return 0 }
        return estimateDailyCost(dailyTokens: todayModelTokens, modelUsage: statsCache.modelUsage)
    }

    public var modelBreakdown: [(name: String, tokens: Int, color: String)] {
        let grouped = groupByFamily(todayModelTokens)
        return grouped.filter { !$0.key.isEmpty && $0.value > 0 }.sorted { $0.value > $1.value }.map { family, tokens in
            let color: String
            switch family {
            case "Fable", "Mythos": color = "teal"
            case "Opus": color = "orange"
            case "Haiku": color = "purple"
            default: color = "blue"
            }
            return (name: family, tokens: tokens, color: color)
        }
    }

    /// Merge stats-cache data with live session data for a complete daily totals picture
    public func dailyTotals(days: Int?) -> [(date: Date, tokens: Int)] {
        let formatter = Self.dateFormatter
        var byDate: [String: Int] = [:]

        // Start with stats-cache data
        if let statsCache {
            for day in statsCache.dailyModelTokens {
                byDate[day.date] = day.tokensByModel.values.reduce(0, +)
            }
        }

        // Overlay live session data (takes precedence for dates it covers)
        for (date, modelTokens) in liveDailyTokens {
            let liveTotal = modelTokens.values.reduce(0, +)
            byDate[date, default: 0] = max(byDate[date] ?? 0, liveTotal)
        }

        var results: [(date: Date, tokens: Int)] = byDate.compactMap { dateStr, tokens in
            guard let date = formatter.date(from: dateStr) else { return nil }
            return (date: date, tokens: tokens)
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
        refreshLock.lock()
        if isRefreshing {
            refreshPending = true
            refreshLock.unlock()
            return
        }
        isRefreshing = true
        refreshPending = false
        refreshLock.unlock()

        isLoading = true
        error = nil

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.refreshLock.lock()
                self.isRefreshing = false
                let hadPending = self.refreshPending
                self.refreshPending = false
                self.refreshLock.unlock()
                // Back to the main actor: refresh() writes the @Observable
                // isLoading/error that SwiftUI reads on main, and this is the
                // only call site that would otherwise re-enter off-main.
                if hadPending {
                    Task { @MainActor in self.refresh() }
                }
            }
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

            // One directory walk feeds both the daily totals and the recent list
            let discovered = (try? SessionDiscovery.discoverSessions(claudeProjectsDir: settings.projectsPath)) ?? []

            // Compute live daily tokens from recent session JSONL files
            let newLiveDailyTokens = self.computeLiveDailyTokens(
                lastComputedDate: newStatsCache?.lastComputedDate,
                sessions: discovered
            )

            let newSessions: [RecentSession] = discovered.prefix(5).map { session in
                let tokenUsage = session.jsonlPath.flatMap { self.usageIndex.tokenUsage(forPath: $0) }
                let cost = tokenUsage.map { CostCalculator.cost(for: $0, customPricing: settings.customPricing) } ?? 0
                let totalTokens = tokenUsage?.displayTokens ?? 0
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

            // An empty discovery means the projects directory was unreadable, not
            // that every session vanished — pruning on that would wipe the index.
            if !discovered.isEmpty {
                self.usageIndex.prune(keeping: Set(discovered.compactMap { $0.jsonlPath }))
            }
            self.usageIndex.save()

            // Fetch API data + check pricing updates (pricing runs unawaited so
            // a slow ~1.7MB price download never blocks the dashboard refresh)
            let newUsageData = await UsageAPIClient.fetchUsage()
            let newProfileData = await UsageAPIClient.fetchProfile()
            Task { await PricingUpdater.checkForUpdates(settings: settings) }

            let finalStats = newStatsCache
            let finalSessions = newSessions
            let finalError = newError
            let finalUsage = newUsageData
            let finalProfile = newProfileData
            let finalLive = newLiveDailyTokens
            await MainActor.run {
                self.statsCache = finalStats
                self.recentSessions = finalSessions
                self.liveDailyTokens = finalLive
                if let finalUsage { self.usageData = finalUsage }
                if let finalProfile { self.profileData = finalProfile }
                if let finalError { self.error = finalError }
                self.lastRefresh = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Live Daily Tokens from JSONL

    /// Fill the gap between the stats cache's last computed day and today from
    /// the live session transcripts. The heavy lifting is delegated to
    /// `JSONLUsageIndex`, which only reads bytes appended since the last pass.
    private func computeLiveDailyTokens(lastComputedDate: String?, sessions: [DiscoveredSession]) -> [String: [String: Int]] {
        let formatter = Self.dateFormatter
        let cutoffDate: Date
        if let lcd = lastComputedDate, let d = formatter.date(from: lcd) {
            cutoffDate = d
        } else {
            // No cache at all — compute last 30 days
            cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        }

        // Only process if there's actually a gap
        guard cutoffDate < Date() else { return [:] }

        let paths = sessions.filter { $0.modified > cutoffDate }.compactMap { $0.jsonlPath }
        return usageIndex.dailyTokens(forPaths: paths, after: cutoffDate)
    }

    // MARK: - Helpers

    /// Estimate daily cost from input+output token totals per model.
    /// Uses weighted average of input/output pricing based on the aggregate ratio.
    private func estimateDailyCost(dailyTokens: [String: Int], modelUsage: [String: ModelUsage]) -> Double {
        dailyTokens.reduce(0.0) { total, pair in
            let (modelId, dailyTotal) = pair
            guard dailyTotal > 0 else { return total }
            let pricing = CostCalculator.pricing(for: modelId, customPricing: settings.customPricing)
            let scale = 1_000_000.0

            // Use the aggregate input/output ratio to split daily tokens
            if let usage = modelUsage[modelId] {
                let io = usage.inputTokens + usage.outputTokens
                if io > 0 {
                    let inputRatio = Double(usage.inputTokens) / Double(io)
                    let outputRatio = Double(usage.outputTokens) / Double(io)
                    let estimatedInput = Double(dailyTotal) * inputRatio
                    let estimatedOutput = Double(dailyTotal) * outputRatio
                    return total + (estimatedInput / scale * pricing.inputPer1M)
                                 + (estimatedOutput / scale * pricing.outputPer1M)
                }
            }
            // Fallback: assume all output (worst case)
            return total + Double(dailyTotal) / scale * pricing.outputPer1M
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

    /// Shared with `JSONLUsageIndex`, which produces the day keys read back here.
    private static let dateFormatter = JSONLUsageIndex.makeDayFormatter()

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
