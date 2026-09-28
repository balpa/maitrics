import Foundation

@Observable
public final class ClaudeDataManager {
    public private(set) var statsCache: StatsCache?
    public private(set) var recentSessions: [RecentSession] = []
    public private(set) var liveDailyTokens: [String: [String: Int]] = [:] // date -> model -> tokens
    public private(set) var liveDailyModelUsage: [String: [String: ModelTokens]] = [:] // date -> model -> full breakdown
    public private(set) var sessionUsage: [SessionUsage] = []
    public private(set) var lastSessionActivity: Date?
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
        let todayStr = Self.dateString(for: Date())
        // Prefer live per-model token data: it has a real input/output split
        // per day, so cost doesn't need the stats cache's aggregate ratio guess
        // — and it's the only source available when the stats cache is stale,
        // missing, or hasn't been written by the CLI yet.
        if let live = liveDailyModelUsage[todayStr] {
            return live.reduce(0.0) { total, pair in
                total + estimatedCost(pair.value, model: pair.key)
            }
        }
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

    /// For each day, the source (stats cache or live scan) with more tokens is used.
    /// `days`: calendar days to today. `nil`: all history.
    public func dailyUsage(days: Int?) -> [UsagePoint] {
        let cutoff = days.map(Self.startOfRange)
        return dayRecords().compactMap { dateStr, record in
            guard let date = Self.dateFormatter.date(from: dateStr) else { return nil }
            if let cutoff, date < cutoff { return nil }
            return UsagePoint(date: date, tokens: record.tokens, cost: record.cost)
        }.sorted { $0.date < $1.date }
    }

    public func usageSummary(days: Int?) -> UsageSummary {
        let cutoff = days.map(Self.startOfRange)
        var summary = UsageSummary()
        var costByFamily: [String: Double] = [:]
        var firstDay: Date?
        for (dateStr, record) in dayRecords() {
            guard let date = Self.dateFormatter.date(from: dateStr) else { continue }
            if let cutoff, date < cutoff { continue }
            guard record.tokens > 0 else { continue }
            summary.totalTokens += record.tokens
            summary.totalCost += record.cost
            summary.activeDays += 1
            firstDay = min(firstDay ?? date, date)
            for (family, cost) in record.costByFamily { costByFamily[family, default: 0] += cost }
        }
        // Idle days are part of the average.
        let rangeDays: Int
        if let days {
            rangeDays = days
        } else if let firstDay {
            rangeDays = (Calendar.current.dateComponents([.day], from: firstDay, to: Calendar.current.startOfDay(for: Date())).day ?? 0) + 1
        } else {
            rangeDays = 0
        }
        summary.averageDailyCost = rangeDays > 0 ? summary.totalCost / Double(rangeDays) : 0
        if let top = costByFamily.max(by: { $0.value < $1.value }), summary.totalCost > 0 {
            summary.topModel = top.key
            summary.topModelShare = top.value / summary.totalCost
        }
        return summary
    }

    public func hourlyUsage(hours: Int) -> [UsagePoint] {
        var byHour: [String: (tokens: Int, cost: Double)] = [:]
        for session in sessionUsage {
            for (hour, models) in session.byHour {
                for (model, tokens) in models {
                    byHour[hour, default: (0, 0)].tokens += tokens.inputTokens + tokens.outputTokens
                    byHour[hour, default: (0, 0)].cost += estimatedCost(tokens, model: model)
                }
            }
        }
        let calendar = Calendar.current
        guard let currentHour = calendar.dateInterval(of: .hour, for: Date())?.start else { return [] }
        return (0..<hours).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .hour, value: -offset, to: currentHour) else { return nil }
            let value = byHour[Self.hourFormatter.string(from: date)] ?? (0, 0)
            return UsagePoint(date: date, tokens: value.tokens, cost: value.cost)
        }
    }

    public func projectBreakdown(days: Int) -> [ProjectUsage] {
        let cutoffKey = Self.dateString(for: Self.startOfRange(days: days))
        var byProject: [String: ProjectUsage] = [:]
        for session in sessionUsage {
            var tokens = 0
            var cost = 0.0
            for (day, models) in session.byDay where day >= cutoffKey {
                for (model, t) in models {
                    tokens += t.inputTokens + t.outputTokens
                    cost += estimatedCost(t, model: model)
                }
            }
            guard tokens > 0 else { continue }
            var project = byProject[session.projectName] ?? ProjectUsage(name: session.projectName)
            project.tokens += tokens
            project.cost += cost
            project.sessions += 1
            byProject[session.projectName] = project
        }
        return byProject.values.sorted { ($0.cost, $0.tokens) > ($1.cost, $1.tokens) }
    }

    private struct DayRecord {
        var tokens = 0
        var cost = 0.0
        var costByFamily: [String: Double] = [:]
    }

    private func dayRecords() -> [String: DayRecord] {
        var records: [String: DayRecord] = [:]
        if let statsCache {
            for day in statsCache.dailyModelTokens {
                var record = DayRecord()
                for (model, tokens) in day.tokensByModel {
                    let cost = estimateDailyCost(dailyTokens: [model: tokens], modelUsage: statsCache.modelUsage)
                    record.tokens += tokens
                    record.cost += cost
                    record.costByFamily[Formatting.shortModelName(model), default: 0] += cost
                }
                records[day.date] = record
            }
        }
        for (date, models) in liveDailyModelUsage {
            var record = DayRecord()
            for (model, tokens) in models {
                let cost = estimatedCost(tokens, model: model)
                record.tokens += tokens.inputTokens + tokens.outputTokens
                record.cost += cost
                record.costByFamily[Formatting.shortModelName(model), default: 0] += cost
            }
            if record.tokens >= (records[date]?.tokens ?? 0) { records[date] = record }
        }
        return records
    }

    /// `days: 7` gives 7 days, today included.
    static func startOfRange(days: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: today) ?? today
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
            let newLiveDailyModelUsage = self.computeLiveDailyModelUsage(
                lastComputedDate: newStatsCache?.lastComputedDate,
                sessions: discovered
            )
            let newSessionUsage = self.computeSessionUsage(sessions: discovered)

            let newSessions: [RecentSession] = discovered.prefix(5).map { session in
                let tokenUsage = SessionTokenUsage.merged(session.usagePaths.compactMap { self.usageIndex.tokenUsage(forPath: $0) })
                let cost = tokenUsage.map { CostCalculator.cost(for: $0, customPricing: settings.customPricing, includeCache: settings.includeCacheInCost) } ?? 0
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
                self.usageIndex.prune(keeping: Set(discovered.flatMap(\.usagePaths)))
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
            let finalLiveModelUsage = newLiveDailyModelUsage
            let finalSessionUsage = newSessionUsage
            let finalLastActivity = discovered.first?.modified
            await MainActor.run {
                self.statsCache = finalStats
                self.recentSessions = finalSessions
                self.liveDailyTokens = finalLive
                self.liveDailyModelUsage = finalLiveModelUsage
                self.sessionUsage = finalSessionUsage
                self.lastSessionActivity = finalLastActivity
                if let finalUsage { self.usageData = finalUsage }
                if let finalProfile { self.profileData = finalProfile }
                if let finalError { self.error = finalError }
                self.lastRefresh = Date()
                self.isLoading = false
            }
        }
    }

    // MARK: - Live Daily Tokens from JSONL

    /// The day after which the stats cache stops covering usage — from here on
    /// out, live JSONL scanning is the only source. No cache at all means the
    /// whole last-30-days window is "the gap".
    private func liveGapCutoffDate(lastComputedDate: String?) -> Date {
        let formatter = Self.dateFormatter
        if let lcd = lastComputedDate, let d = formatter.date(from: lcd) {
            return d
        }
        return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
    }

    /// Fill the gap between the stats cache's last computed day and today from
    /// the live session transcripts. The heavy lifting is delegated to
    /// `JSONLUsageIndex`, which only reads bytes appended since the last pass.
    private func computeLiveDailyTokens(lastComputedDate: String?, sessions: [DiscoveredSession]) -> [String: [String: Int]] {
        let cutoffDate = liveGapCutoffDate(lastComputedDate: lastComputedDate)
        // Only process if there's actually a gap
        guard cutoffDate < Date() else { return [:] }

        let paths = sessions.filter { $0.modified > cutoffDate }.flatMap(\.usagePaths)
        return usageIndex.dailyTokens(forPaths: paths, after: cutoffDate)
    }

    /// Same gap-filling as `computeLiveDailyTokens`, but keeping the full
    /// input/output/cache breakdown per model so cost can be computed directly
    /// instead of estimated from an aggregate ratio.
    private func computeLiveDailyModelUsage(lastComputedDate: String?, sessions: [DiscoveredSession]) -> [String: [String: ModelTokens]] {
        let cutoffDate = liveGapCutoffDate(lastComputedDate: lastComputedDate)
        guard cutoffDate < Date() else { return [:] }

        let paths = sessions.filter { $0.modified > cutoffDate }.flatMap(\.usagePaths)
        return usageIndex.dailyModelUsage(forPaths: paths, after: cutoffDate)
    }

    private func computeSessionUsage(sessions: [DiscoveredSession]) -> [SessionUsage] {
        let cutoff = Self.startOfRange(days: 30)
        return sessions.filter { $0.modified >= cutoff }.compactMap { session in
            let files = session.usagePaths.compactMap { usageIndex.fileUsage(forPath: $0) }
            guard !files.isEmpty else { return nil }
            return SessionUsage(sessionId: session.sessionId, projectName: session.projectName,
                                byDay: ModelTokens.merged(files.map(\.byDay)),
                                byHour: ModelTokens.merged(files.map(\.byHour)))
        }
    }

    // MARK: - Helpers

    private func estimatedCost(_ tokens: ModelTokens, model: String) -> Double {
        CostCalculator.cost(for: tokens, model: model, customPricing: settings.customPricing, includeCache: settings.includeCacheInCost)
    }

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
                    var cost = (estimatedInput / scale * pricing.inputPer1M)
                             + (estimatedOutput / scale * pricing.outputPer1M)
                    // The stats cache has no daily cache tokens. Use the same aggregate ratio.
                    if settings.includeCacheInCost {
                        let perIOToken = Double(dailyTotal) / Double(io)
                        cost += Double(usage.cacheReadInputTokens) * perIOToken / scale * pricing.cacheReadPer1M
                              + Double(usage.cacheCreationInputTokens) * perIOToken / scale * pricing.cacheWritePer1M
                    }
                    return total + cost
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
    private static let hourFormatter = JSONLUsageIndex.makeHourFormatter()

    static func dateString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

public struct UsagePoint: Identifiable, Sendable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let tokens: Int
    public let cost: Double

    public init(date: Date, tokens: Int, cost: Double) {
        self.date = date
        self.tokens = tokens
        self.cost = cost
    }
}

public struct UsageSummary: Sendable, Equatable {
    public var totalCost: Double = 0
    public var totalTokens: Int = 0
    public var averageDailyCost: Double = 0
    public var activeDays: Int = 0
    public var topModel: String?
    public var topModelShare: Double = 0

    public init() {}
}

public struct ProjectUsage: Identifiable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public var tokens: Int = 0
    public var cost: Double = 0
    public var sessions: Int = 0

    public init(name: String, tokens: Int = 0, cost: Double = 0, sessions: Int = 0) {
        self.name = name
        self.tokens = tokens
        self.cost = cost
        self.sessions = sessions
    }
}

public struct SessionUsage: Sendable {
    public let sessionId: String
    public let projectName: String
    public let byDay: [String: [String: ModelTokens]]
    public let byHour: [String: [String: ModelTokens]]
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
