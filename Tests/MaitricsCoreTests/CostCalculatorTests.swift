import XCTest
@testable import MaitricsCore

final class CostCalculatorTests: XCTestCase {
    func testFableCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-fable-5")
        // $10 + $50 + $1.00 + $12.50 = $73.50
        XCTAssertEqual(cost, 73.50, accuracy: 0.01)
    }

    func testMythosUsesFablePricing() {
        XCTAssertEqual(CostCalculator.modelFamily("claude-mythos-5"), "fable")
    }

    func testOpusCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-opus-5")
        // $5 + $25 + $0.50 + $6.25 = $36.75
        XCTAssertEqual(cost, 36.75, accuracy: 0.01)
    }

    func testSonnetCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-sonnet-5")
        // $3 + $15 + $0.30 + $3.75 = $22.05
        XCTAssertEqual(cost, 22.05, accuracy: 0.01)
    }

    func testHaikuCostCalculation() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 1_000_000, cacheCreationInputTokens: 1_000_000, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-haiku-4-5-20251001")
        // $1 + $5 + $0.10 + $1.25 = $7.35
        XCTAssertEqual(cost, 7.35, accuracy: 0.01)
    }

    func testUnknownModelUsesDefaultPricing() {
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, model: "claude-unknown-99")
        // Falls back to Sonnet: $3 + $15 = $18
        XCTAssertEqual(cost, 18.0, accuracy: 0.01)
    }

    func testTotalCostFromModelUsageDict() {
        let usage: [String: ModelUsage] = [
            "claude-opus-5": ModelUsage(inputTokens: 100_000, outputTokens: 100_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0),
            "claude-haiku-4-5-20251001": ModelUsage(inputTokens: 100_000, outputTokens: 100_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0),
        ]
        let total = CostCalculator.totalCost(modelUsage: usage)
        // Opus: $0.50 + $2.50 = $3.00. Haiku: $0.10 + $0.50 = $0.60. Total: $3.60
        XCTAssertEqual(total, 3.60, accuracy: 0.01)
    }

    func testCostFromSessionTokenUsage() {
        let session = SessionTokenUsage(byModel: [
            "claude-opus-5": ModelTokens(inputTokens: 300, outputTokens: 1300, cacheReadInputTokens: 13000, cacheCreationInputTokens: 3000)
        ])
        let cost = CostCalculator.cost(for: session)
        // Input+output only: (300/1M*5) + (1300/1M*25) = 0.0015 + 0.0325 = 0.034
        XCTAssertEqual(cost, 0.034, accuracy: 0.001)
    }

    func testCustomPricingOverride() {
        let pricing = PricingTier(inputPer1M: 100, outputPer1M: 200, cacheReadPer1M: 10, cacheWritePer1M: 50)
        let usage = ModelUsage(inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadInputTokens: 0, cacheCreationInputTokens: 0, webSearchRequests: 0, costUSD: 0)
        let cost = CostCalculator.cost(for: usage, pricing: pricing)
        XCTAssertEqual(cost, 300.0, accuracy: 0.01)
    }
}
