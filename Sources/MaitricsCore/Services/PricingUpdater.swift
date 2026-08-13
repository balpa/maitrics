import Foundation

/// Keeps model pricing current by fetching LiteLLM's continuously-maintained
/// price table (the same source ccusage and similar tools use). Falls back to
/// the built-in defaults in `CostCalculator` when offline.
public enum PricingUpdater {
    private static let remoteURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static let localCacheFile = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/maitrics-pricing-cache.json")
    private static let checkInterval: TimeInterval = 86400 // 24 hours after a successful fetch
    private static let retryInterval: TimeInterval = 3600  // 1 hour after a failed attempt

    // In-memory tables, written by the background refresh task and read from the
    // main actor (UI + cost estimation) — every access goes through `lock`.
    private static let lock = NSLock()
    private static var models: [String: PricingTier] = [:]
    private static var families: [String: PricingTier]?
    private static var fetchedAt: String?
    private static var lastAttemptAt: Date?
    private static var isFetching = false

    /// Exact per-model pricing (keyed by full model id, e.g. "claude-opus-4-1").
    public static var modelPricing: [String: PricingTier] {
        lock.withLock { models }
    }

    /// Family-level pricing (fable/opus/sonnet/haiku) derived from the current
    /// flagship model of each family; built-in defaults when nothing is loaded.
    public static var effectivePricing: [String: PricingTier] {
        lock.withLock { families } ?? CostCalculator.defaultPricing
    }

    public static var lastUpdateDate: String? {
        lock.withLock { fetchedAt }
    }

    /// Fetches the latest pricing if the local cache is older than 24h.
    /// Call on app launch and periodically. `force` skips the freshness and
    /// retry throttles (for the Settings refresh button) but never overlaps
    /// an in-flight fetch.
    public static func checkForUpdates(settings: AppSettings, force: Bool = false) async {
        // Skip if user has custom pricing set manually
        if settings.customPricing != nil { return }

        // Fresh successful fetch cached within the last 24h — nothing to do
        if !force,
           let attrs = try? FileManager.default.attributesOfItem(atPath: localCacheFile.path),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < checkInterval,
           decodeCache((try? Data(contentsOf: localCacheFile)) ?? Data()) != nil {
            return
        }

        // Throttle attempts (not just successes) — refresh() fires on every
        // stats-cache file-watch event, and the price table is a ~1.7MB download.
        guard beginFetchIfAllowed(now: Date(), force: force) else { return }
        defer { endFetch() }

        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let parsed = parseLiteLLM(data)
            guard !parsed.isEmpty else { return }

            let dateStr = Self.dateFormatter.string(from: Date())
            apply(models: parsed, fetchedAt: dateStr)

            // Persist a compact cache (not the full multi-MB LiteLLM file)
            if let cache = try? encodeCache(models: parsed, fetchedAt: dateStr) {
                try? FileManager.default.createDirectory(
                    at: localCacheFile.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? cache.write(to: localCacheFile)
            }
        } catch {
            // Silently fail — use existing defaults
        }
    }

    /// Load cached pricing on app start (before network is available).
    /// Legacy family-format caches fail to decode and are simply ignored.
    public static func loadCachedPricing() {
        guard let data = try? Data(contentsOf: localCacheFile),
              let cache = decodeCache(data) else { return }
        apply(models: cache.models, fetchedAt: cache.fetchedAt)
    }

    // MARK: - Internal (testable)

    struct CacheFile: Codable {
        let fetchedAt: String
        let models: [String: PricingTier]
    }

    /// Extracts anthropic `claude-*` entries from LiteLLM's price table,
    /// converting per-token costs to per-1M rates.
    static func parseLiteLLM(_ data: Data) -> [String: PricingTier] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }

        var result: [String: PricingTier] = [:]
        for (key, value) in json {
            guard key.hasPrefix("claude-"),
                  let m = value as? [String: Any],
                  m["litellm_provider"] as? String == "anthropic",
                  let input = m["input_cost_per_token"] as? Double,
                  let output = m["output_cost_per_token"] as? Double else { continue }

            let scale = 1_000_000.0
            result[key.lowercased()] = PricingTier(
                inputPer1M: input * scale,
                outputPer1M: output * scale,
                cacheReadPer1M: ((m["cache_read_input_token_cost"] as? Double) ?? input * 0.1) * scale,
                cacheWritePer1M: ((m["cache_creation_input_token_cost"] as? Double) ?? input * 1.25) * scale
            )
        }
        return result
    }

    static func apply(models newModels: [String: PricingTier], fetchedAt date: String?) {
        let newFamilies = deriveFamilies(from: newModels)
        lock.withLock {
            models = newModels
            families = newFamilies
            fetchedAt = date
        }
    }

    /// Marks a fetch attempt if none is in flight and the retry interval has
    /// passed since the last attempt (`force` skips the interval check).
    /// Callers must pair with `endFetch()`.
    static func beginFetchIfAllowed(now: Date, force: Bool = false) -> Bool {
        lock.withLock {
            if isFetching { return false }
            if !force, let last = lastAttemptAt, now.timeIntervalSince(last) < retryInterval { return false }
            isFetching = true
            lastAttemptAt = now
            return true
        }
    }

    static func endFetch() {
        lock.withLock { isFetching = false }
    }

    static func resetFetchStateForTesting() {
        lock.withLock {
            isFetching = false
            lastAttemptAt = nil
        }
    }

    /// Family rates come from each family's current flagship model; families
    /// missing from the fetched table keep the built-in defaults.
    private static func deriveFamilies(from models: [String: PricingTier]) -> [String: PricingTier] {
        let representatives = [
            "fable": "claude-fable-5",
            "opus": "claude-opus-5",
            "sonnet": "claude-sonnet-5",
            "haiku": "claude-haiku-4-5",
        ]
        var result = CostCalculator.defaultPricing
        for (family, modelId) in representatives {
            if let tier = models[modelId] { result[family] = tier }
        }
        return result
    }

    static func encodeCache(models: [String: PricingTier], fetchedAt: String) throws -> Data {
        try JSONEncoder().encode(CacheFile(fetchedAt: fetchedAt, models: models))
    }

    static func decodeCache(_ data: Data) -> CacheFile? {
        try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
