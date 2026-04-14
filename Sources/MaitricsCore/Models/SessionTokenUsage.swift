import Foundation

public struct SessionTokenUsage: Sendable {
    public let byModel: [String: ModelTokens]

    public var totalInputTokens: Int { byModel.values.reduce(0) { $0 + $1.inputTokens } }
    public var totalOutputTokens: Int { byModel.values.reduce(0) { $0 + $1.outputTokens } }
    public var totalCacheReadTokens: Int { byModel.values.reduce(0) { $0 + $1.cacheReadInputTokens } }
    public var totalCacheWriteTokens: Int { byModel.values.reduce(0) { $0 + $1.cacheCreationInputTokens } }
    public var totalTokens: Int { byModel.values.reduce(0) { $0 + $1.totalTokens } }
}

public struct ModelTokens: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public var totalTokens: Int { inputTokens + outputTokens + cacheReadInputTokens + cacheCreationInputTokens }

    public static let zero = ModelTokens(inputTokens: 0, outputTokens: 0, cacheReadInputTokens: 0, cacheCreationInputTokens: 0)
}
