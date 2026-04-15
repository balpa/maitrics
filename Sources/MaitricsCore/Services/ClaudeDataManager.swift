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

    private let settings: AppSettings
    private var sessionTokenCache: [String: (mtime: Date, usage: SessionTokenUsage)] = [:]

    public init(settings: AppSettings = AppSettings()) {
        self.settings = settings
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

            // Compute live daily tokens from recent session JSONL files
            let newLiveDailyTokens = self.computeLiveDailyTokens(
                lastComputedDate: newStatsCache?.lastComputedDate,
                projectsDir: settings.projectsPath
            )

            // Discover sessions
            var newSessions: [RecentSession] = []
            if let discovered = try? SessionDiscovery.discoverSessions(claudeProjectsDir: settings.projectsPath) {
                let topSessions = Array(discovered.prefix(5))
                newSessions = topSessions.map { session in
                    let tokenUsage = self.cachedTokenUsage(for: session, settings: settings)
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
            }

            // Fetch API data
            let newUsageData = await UsageAPIClient.fetchUsage()
            let newProfileData = await UsageAPIClient.fetchProfile()

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

    /// Scan recent session JSONL files for dates after lastComputedDate to fill the gap
    private func computeLiveDailyTokens(lastComputedDate: String?, projectsDir: URL) -> [String: [String: Int]] {
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

        var dailyTokens: [String: [String: Int]] = [:] // date -> model -> tokens

        guard let discovered = try? SessionDiscovery.discoverSessions(claudeProjectsDir: projectsDir) else { return [:] }

        // Only process sessions modified after the cutoff
        let recentSessions = discovered.filter { $0.modified > cutoffDate }

        for session in recentSessions {
            guard let path = session.jsonlPath else { continue }
            let fileURL = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      obj["type"] as? String == "assistant",
                      let message = obj["message"] as? [String: Any],
                      let model = message["model"] as? String,
                      let usage = message["usage"] as? [String: Any] else { continue }

                // Get the timestamp for this message to determine which day
                let dateStr: String
                if let timestamp = obj["timestamp"] as? String,
                   let msgDate = SessionDiscovery.parseDate(timestamp) as Date?,
                   msgDate != Date.distantPast {
                    dateStr = formatter.string(from: msgDate)
                } else {
                    dateStr = formatter.string(from: session.modified)
                }

                // Only count dates after the cutoff
                guard let dayDate = formatter.date(from: dateStr), dayDate > cutoffDate else { continue }

                // Only count input + output (matches stats-cache.json; excludes cache tokens)
                let output = usage["output_tokens"] as? Int ?? 0
                let input = usage["input_tokens"] as? Int ?? 0
                let total = input + output

                dailyTokens[dateStr, default: [:]][model, default: 0] += total
            }
        }

        return dailyTokens
    }

    // MARK: - Helpers

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
