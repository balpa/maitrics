import Foundation

public struct SessionTokenUsage: Sendable {
    public let byModel: [String: ModelTokens]

    public init(byModel: [String: ModelTokens]) {
        self.byModel = byModel
    }

    public var totalInputTokens: Int { byModel.values.reduce(0) { $0 + $1.inputTokens } }
    public var totalOutputTokens: Int { byModel.values.reduce(0) { $0 + $1.outputTokens } }
    public var totalCacheReadTokens: Int { byModel.values.reduce(0) { $0 + $1.cacheReadInputTokens } }
    public var totalCacheWriteTokens: Int { byModel.values.reduce(0) { $0 + $1.cacheCreationInputTokens } }
    public var totalTokens: Int { byModel.values.reduce(0) { $0 + $1.totalTokens } }
    /// Input + output only (excludes cache) — matches stats-cache.json daily totals
    public var displayTokens: Int { totalInputTokens + totalOutputTokens }
}

public struct ModelTokens: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadInputTokens: Int, cacheCreationInputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens }

    public static let zero = ModelTokens(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
}
