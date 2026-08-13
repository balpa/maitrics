import Foundation

public struct PricingTier: Codable, Sendable {
    public var inputPer1M: Double
    public var outputPer1M: Double
    public var cacheReadPer1M: Double
    public var cacheWritePer1M: Double

    public init(inputPer1M: Double, outputPer1M: Double, cacheReadPer1M: Double, cacheWritePer1M: Double) {
        self.inputPer1M = inputPer1M
        self.outputPer1M = outputPer1M
        self.cacheReadPer1M = cacheReadPer1M
        self.cacheWritePer1M = cacheWritePer1M
    }
}

public enum CostCalculator {
    public static let defaultPricing: [String: PricingTier] = [
        "fable": PricingTier(inputPer1M: 10, outputPer1M: 50, cacheReadPer1M: 1.0, cacheWritePer1M: 12.5),
        "opus": PricingTier(inputPer1M: 5, outputPer1M: 25, cacheReadPer1M: 0.5, cacheWritePer1M: 6.25),
        "sonnet": PricingTier(inputPer1M: 3, outputPer1M: 15, cacheReadPer1M: 0.3, cacheWritePer1M: 3.75),
        "haiku": PricingTier(inputPer1M: 1, outputPer1M: 5, cacheReadPer1M: 0.1, cacheWritePer1M: 1.25),
    ]

    public static func modelFamily(_ modelId: String) -> String {
        let lower = modelId.lowercased()
        // Fable/Mythos share the same pricing tier
        if lower.contains("fable") || lower.contains("mythos") { return "fable" }
        if lower.contains("opus") { return "opus" }
        if lower.contains("haiku") { return "haiku" }
        return "sonnet"
    }

    public static func pricing(for modelId: String, customPricing: [String: PricingTier]? = nil) -> PricingTier {
        let key = modelId.lowercased()
        let family = modelFamily(modelId)
        if let custom = customPricing?[key] ?? customPricing?[family] { return custom }
        // Exact model match from the dynamically fetched table (handles legacy
        // models like claude-opus-4-1 whose price differs from the family rate)
        if let exact = PricingUpdater.modelPricing[key] { return exact }
        return PricingUpdater.effectivePricing[family] ?? defaultPricing[family] ?? defaultPricing["sonnet"]!
    }

    public static func cost(for usage: ModelUsage, model: String, customPricing: [String: PricingTier]? = nil) -> Double {
        let p = pricing(for: model, customPricing: customPricing)
        return cost(for: usage, pricing: p)
    }

    public static func cost(for usage: ModelUsage, pricing p: PricingTier) -> Double {
        let scale = 1_000_000.0
        return (Double(usage.inputTokens) / scale * p.inputPer1M)
             + (Double(usage.outputTokens) / scale * p.outputPer1M)
             + (Double(usage.cacheReadInputTokens) / scale * p.cacheReadPer1M)
             + (Double(usage.cacheCreationInputTokens) / scale * p.cacheWritePer1M)
    }

    public static func totalCost(modelUsage: [String: ModelUsage], customPricing: [String: PricingTier]? = nil) -> Double {
        modelUsage.reduce(0.0) { total, pair in
            total + cost(for: pair.value, model: pair.key, customPricing: customPricing)
        }
    }

    /// Cost from input+output tokens only (excludes cache — appropriate for subscription users)
    public static func cost(for session: SessionTokenUsage, customPricing: [String: PricingTier]? = nil) -> Double {
        session.byModel.reduce(0.0) { total, pair in
            let p = pricing(for: pair.key, customPricing: customPricing)
            let tokens = pair.value
            let scale = 1_000_000.0
            return total
                + (Double(tokens.inputTokens) / scale * p.inputPer1M)
                + (Double(tokens.outputTokens) / scale * p.outputPer1M)
        }
    }
}
