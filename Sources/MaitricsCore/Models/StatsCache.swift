import Foundation

public struct StatsCache: Codable, Sendable {
    public let version: Int
    public let lastComputedDate: String
    public let dailyActivity: [DailyActivity]
    public let dailyModelTokens: [DailyModelTokens]
    public let modelUsage: [String: ModelUsage]
    public let totalSessions: Int
    public let totalMessages: Int
    public let longestSession: LongestSession?
    public let firstSessionDate: String?
    public let hourCounts: [String: Int]?
}

public struct DailyActivity: Codable, Sendable {
    public let date: String
    public let messageCount: Int
    public let sessionCount: Int
    public let toolCallCount: Int
}

public struct DailyModelTokens: Codable, Sendable {
    public let date: String
    public let tokensByModel: [String: Int]
}

public struct ModelUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadInputTokens: Int
    public let cacheCreationInputTokens: Int
    public let webSearchRequests: Int?
    public let costUSD: Double?

    public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int, webSearchRequests: Int?, costUSD: Double?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.webSearchRequests = webSearchRequests
        self.costUSD = costUSD
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }
}

public struct LongestSession: Codable, Sendable {
    public let sessionId: String
    public let duration: Int
    public let messageCount: Int
    public let timestamp: String
}
