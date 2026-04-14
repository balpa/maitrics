import XCTest
@testable import MaitricsCore

final class CostCalculatorTests: XCTestCase {
    func testOpusCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-opus-4-6")
        // $15 + $75 + $1.50 + $18.75 = $110.25
        XCTAssertEqual(cost, 110.25, accuracy: 0.01)
    }

    func testSonnetCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-sonnet-4-6")
        // $3 + $15 + $0.30 + $3.75 = $22.05
        XCTAssertEqual(cost, 22.05, accuracy: 0.01)
    }

    func testHaikuCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-haiku-4-5-20251001")
        // $0.80 + $4 + $0.08 + $1.00 = $5.88
        XCTAssertEqual(cost, 5.88, accuracy: 0.01)
    }

    func testUnknownModelUsesDefaultPricing() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-unknown-99")
        // Falls back to Sonnet: $3 + $15 = $18
        XCTAssertEqual(cost, 18.0, accuracy: 0.01)
    }

    func testTotalCostFromModelUsageDict() {
        let usage: [String: ModelUsage] = [
            "claude-opus-4-6": ModelUsage(inputTokens: 100_000, outputTokens: 100_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0),
            "claude-haiku-4-5-20251001": ModelUsage(inputTokens: 100_000, outputTokens: 100_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0),
        ]
        let total = CostCalculator.totalCost(modelUsage: usage)
        // Opus: $1.50 + $7.50 = $9.00. Haiku: $0.08 + $0.40 = $0.48. Total: $9.48
        XCTAssertEqual(total, 9.48, accuracy: 0.01)
    }

    func testCostFromSessionTokenUsage() {
        let session = SessionTokenUsage(byModel: [
            "claude-opus-4-6": ModelTokens(inputTokens: 300, outputTokens: 1300, cacheReadInputTokens: 13000, cacheCreationInputTokens: 3000)
        ])
        let cost = CostCalculator.cost(for: session)
        // (300/1M*15) + (1300/1M*75) + (13000/1M*1.5) + (3000/1M*18.75) = 0.17775
        XCTAssertEqual(cost, 0.17775, accuracy: 0.001)
    }

    func testCustomPricingOverride() {
        let pricing = PricingTier(inputPer1M: 100, outputPer1M: 200, cacheReadPer1M: 10, cacheWritePer1M: 50)
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, pricing: pricing)
        XCTAssertEqual(cost, 300.0, accuracy: 0.01)
    }
}
