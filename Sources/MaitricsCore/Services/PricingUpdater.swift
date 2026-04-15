import Foundation

public enum PricingUpdater {
    // Update this URL if the repo changes
    private static let remoteURL = URL(string: "https://raw.githubusercontent.com/balpa/maitrics/main/Resources/pricing.json")!
    private static let localCacheFile = URL(fileURLWithPath: NSHomeDirectory() + "/.claude/maitrics-pricing-cache.json")
    private static let checkInterval: TimeInterval = 86400 // 24 hours

    /// Fetches latest pricing, updates settings if newer version found.
    /// Call on app launch and periodically.
    public static func checkForUpdates(settings: AppSettings) async {
        // Skip if user has custom pricing set manually
        if settings.customPricing != nil { return }

        // Check if we fetched recently
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localCacheFile.path),
           let mtime = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < checkInterval {
            return
        }

        // Fetch remote pricing
        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            // Parse and validate
            guard let pricing = parsePricingJSON(data) else { return }

            // Check if version is newer than what we have cached
            let cachedVersion = readCachedVersion()
            if let remoteVersion = pricing.version, remoteVersion > (cachedVersion ?? "") {
                // Update the default pricing in CostCalculator
                applyPricing(pricing.models)

                // Cache the response
                try? data.write(to: localCacheFile)
            }
        } catch {
            // Silently fail — use existing defaults
        }
    }

    /// Load cached pricing on app start (before network is available)
    public static func loadCachedPricing() {
        guard let data = try? Data(contentsOf: localCacheFile),
              let pricing = parsePricingJSON(data) else { return }
        applyPricing(pricing.models)
    }

    public static var lastUpdateDate: String? {
        readCachedVersion()
    }

    // MARK: - Internal

    private struct PricingFile {
        let version: String?
        let models: [String: PricingTier]
    }

    private static func parsePricingJSON(_ data: Data) -> PricingFile? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsJSON = json["models"] as? [String: Any] else { return nil }

        var models: [String: PricingTier] = [:]
        for (key, value) in modelsJSON {
            guard let m = value as? [String: Any] else { continue }
            models[key] = PricingTier(
                inputPer1M: m["inputPer1M"] as? Double ?? 0,
                outputPer1M: m["outputPer1M"] as? Double ?? 0,
                cacheReadPer1M: m["cacheReadPer1M"] as? Double ?? 0,
                cacheWritePer1M: m["cacheWritePer1M"] as? Double ?? 0
            )
        }

        return PricingFile(version: json["version"] as? String, models: models)
    }

    private static func applyPricing(_ models: [String: PricingTier]) {
        // Update the static default pricing used by CostCalculator
        // Since defaultPricing is a let, we store updates in UserDefaults
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: "latestPricing")
            UserDefaults.standard.set(Date(), forKey: "latestPricingDate")
        }
    }

    private static func readCachedVersion() -> String? {
        guard let data = try? Data(contentsOf: localCacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    /// Get the effective pricing (remote-updated or built-in defaults)
    public static var effectivePricing: [String: PricingTier] {
        if let data = UserDefaults.standard.data(forKey: "latestPricing"),
           let pricing = try? JSONDecoder().decode([String: PricingTier].self, from: data) {
            return pricing
        }
        return CostCalculator.defaultPricing
    }
}
