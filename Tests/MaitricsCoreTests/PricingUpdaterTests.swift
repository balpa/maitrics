import XCTest
@testable import MaitricsCore

final class PricingUpdaterTests: XCTestCase {
    override func tearDown() {
        PricingUpdater.apply(models: [:], fetchedAt: nil)
        PricingUpdater.resetFetchStateForTesting()
        super.tearDown()
    }

    private let sampleLiteLLM = """
    {
      "claude-opus-5": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 5e-06,
        "output_cost_per_token": 2.5e-05,
        "cache_read_input_token_cost": 5e-07,
        "cache_creation_input_token_cost": 6.25e-06
      },
      "claude-fable-5": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 1e-05,
        "output_cost_per_token": 5e-05,
        "cache_read_input_token_cost": 1e-06,
        "cache_creation_input_token_cost": 1.25e-05
      },
      "claude-opus-4-1": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 1.5e-05,
        "output_cost_per_token": 7.5e-05,
        "cache_read_input_token_cost": 1.5e-06,
        "cache_creation_input_token_cost": 1.875e-05
      },
      "claude-sonnet-5": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 2e-06,
        "output_cost_per_token": 1e-05,
        "cache_read_input_token_cost": 2e-07,
        "cache_creation_input_token_cost": 2.5e-06
      },
      "claude-haiku-4-5": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 1e-06,
        "output_cost_per_token": 5e-06,
        "cache_read_input_token_cost": 1e-07,
        "cache_creation_input_token_cost": 1.25e-06
      },
      "claude-opus-5-no-output": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 5e-06
      },
      "vertex_ai/claude-opus-5": {
        "litellm_provider": "vertex_ai",
        "input_cost_per_token": 5e-06,
        "output_cost_per_token": 2.5e-05
      },
      "gpt-x": {
        "litellm_provider": "openai",
        "input_cost_per_token": 1e-06,
        "output_cost_per_token": 2e-06
      }
    }
    """.data(using: .utf8)!

    func testParseLiteLLMExtractsAnthropicClaudeModels() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        XCTAssertNotNil(models["claude-opus-5"])
        XCTAssertNotNil(models["claude-fable-5"])
        XCTAssertNil(models["gpt-x"])
        XCTAssertNil(models["vertex_ai/claude-opus-5"], "non-anthropic providers should be skipped")
        XCTAssertNil(models["claude-opus-5-no-output"], "entries without output cost should be skipped")
    }

    func testParseLiteLLMConvertsPerTokenToPer1M() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        let opus = models["claude-opus-5"]!
        XCTAssertEqual(opus.inputPer1M, 5.0, accuracy: 0.001)
        XCTAssertEqual(opus.outputPer1M, 25.0, accuracy: 0.001)
        XCTAssertEqual(opus.cacheReadPer1M, 0.5, accuracy: 0.001)
        XCTAssertEqual(opus.cacheWritePer1M, 6.25, accuracy: 0.001)
    }

    func testApplyUpdatesEffectiveFamilyPricing() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        PricingUpdater.apply(models: models, fetchedAt: "2026-08-13")

        let effective = PricingUpdater.effectivePricing
        // Sonnet family derives from claude-sonnet-5 ($2/$10 intro pricing in fixture)
        XCTAssertEqual(effective["sonnet"]!.inputPer1M, 2.0, accuracy: 0.001)
        XCTAssertEqual(effective["fable"]!.inputPer1M, 10.0, accuracy: 0.001)
        XCTAssertEqual(PricingUpdater.lastUpdateDate, "2026-08-13")
    }

    func testExactModelPricingBeatsFamilyPricing() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        PricingUpdater.apply(models: models, fetchedAt: "2026-08-13")

        // Legacy opus 4.1 keeps its own $15/$75 pricing instead of the $5/$25 family rate
        let tier = CostCalculator.pricing(for: "claude-opus-4-1")
        XCTAssertEqual(tier.inputPer1M, 15.0, accuracy: 0.001)
        XCTAssertEqual(tier.outputPer1M, 75.0, accuracy: 0.001)
    }

    func testUnknownModelFallsBackToFamily() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        PricingUpdater.apply(models: models, fetchedAt: "2026-08-13")

        // Dated variant not in the table → opus family rate from claude-opus-5
        let tier = CostCalculator.pricing(for: "claude-opus-9-20990101")
        XCTAssertEqual(tier.inputPer1M, 5.0, accuracy: 0.001)
    }

    func testEmptyTableFallsBackToBuiltInDefaults() {
        PricingUpdater.apply(models: [:], fetchedAt: nil)
        let effective = PricingUpdater.effectivePricing
        XCTAssertEqual(effective["opus"]!.inputPer1M, CostCalculator.defaultPricing["opus"]!.inputPer1M)
        XCTAssertNil(PricingUpdater.lastUpdateDate)
    }

    func testCacheRoundTrip() throws {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        let data = try PricingUpdater.encodeCache(models: models, fetchedAt: "2026-08-13")
        let decoded = try XCTUnwrap(PricingUpdater.decodeCache(data))
        XCTAssertEqual(decoded.fetchedAt, "2026-08-13")
        XCTAssertEqual(decoded.models["claude-fable-5"]!.outputPer1M, 50.0, accuracy: 0.001)
    }

    func testFetchAttemptThrottling() {
        let t0 = Date()
        // First attempt allowed
        XCTAssertTrue(PricingUpdater.beginFetchIfAllowed(now: t0))
        // Concurrent attempt blocked while in flight
        XCTAssertFalse(PricingUpdater.beginFetchIfAllowed(now: t0))
        PricingUpdater.endFetch()
        // Retry throttled even after a failed attempt (no cache written)
        XCTAssertFalse(PricingUpdater.beginFetchIfAllowed(now: t0.addingTimeInterval(60)))
        // Allowed again after the retry interval passes
        XCTAssertTrue(PricingUpdater.beginFetchIfAllowed(now: t0.addingTimeInterval(3700)))
        PricingUpdater.endFetch()
    }

    func testForcedFetchBypassesRetryThrottle() {
        let t0 = Date()
        XCTAssertTrue(PricingUpdater.beginFetchIfAllowed(now: t0))
        PricingUpdater.endFetch()
        // Within the retry window a normal attempt is blocked, a forced one is not
        XCTAssertFalse(PricingUpdater.beginFetchIfAllowed(now: t0.addingTimeInterval(60)))
        XCTAssertTrue(PricingUpdater.beginFetchIfAllowed(now: t0.addingTimeInterval(60), force: true))
        // ...but force never overlaps an in-flight fetch
        XCTAssertFalse(PricingUpdater.beginFetchIfAllowed(now: t0.addingTimeInterval(61), force: true))
        PricingUpdater.endFetch()
    }

    func testParseLiteLLMLowercasesKeys() {
        let mixedCase = """
        {
          "claude-Opus-Test": {
            "litellm_provider": "anthropic",
            "input_cost_per_token": 5e-06,
            "output_cost_per_token": 2.5e-05
          }
        }
        """.data(using: .utf8)!
        let models = PricingUpdater.parseLiteLLM(mixedCase)
        XCTAssertNotNil(models["claude-opus-test"])
        XCTAssertNil(models["claude-Opus-Test"])
    }

    func testConcurrentApplyAndReadDoesNotCrash() {
        let models = PricingUpdater.parseLiteLLM(sampleLiteLLM)
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            if i % 2 == 0 {
                PricingUpdater.apply(models: models, fetchedAt: "2026-08-13")
            } else {
                _ = PricingUpdater.modelPricing["claude-opus-5"]
                _ = PricingUpdater.effectivePricing["opus"]
                _ = CostCalculator.pricing(for: "claude-opus-4-1")
            }
        }
        XCTAssertEqual(PricingUpdater.modelPricing["claude-opus-5"]!.inputPer1M, 5.0, accuracy: 0.001)
    }

    func testLegacyCacheFormatIsRejected() {
        let legacy = """
        {"version": "2025-04-15", "models": {"opus": {"inputPer1M": 15}}}
        """.data(using: .utf8)!
        XCTAssertNil(PricingUpdater.decodeCache(legacy))
    }
}
