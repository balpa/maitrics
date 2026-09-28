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

    /// `nil` if `usages` is empty.
    public static func merged(_ usages: [SessionTokenUsage]) -> SessionTokenUsage? {
        guard !usages.isEmpty else { return nil }
        var byModel: [String: ModelTokens] = [:]
        for usage in usages {
            for (model, tokens) in usage.byModel { byModel[model, default: .zero].add(tokens) }
        }
        return SessionTokenUsage(byModel: byModel)
    }
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

    public mutating func add(_ other: ModelTokens) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadInputTokens += other.cacheReadInputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
    }

    /// Sums `key -> model -> tokens` maps.
    public static func merged(_ maps: [[String: [String: ModelTokens]]]) -> [String: [String: ModelTokens]] {
        var result: [String: [String: ModelTokens]] = [:]
        for map in maps {
            for (key, models) in map {
                for (model, tokens) in models { result[key, default: [:]][model, default: .zero].add(tokens) }
            }
        }
        return result
    }
}
