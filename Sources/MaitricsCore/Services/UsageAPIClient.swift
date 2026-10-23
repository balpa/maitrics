import Foundation
import Security

// MARK: - Models

public struct UsageData: Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let sevenDaySonnet: UsageWindow?
    public let sevenDayOpus: UsageWindow?
    public let modelLimits: [ModelLimit]
    public let extraUsage: ExtraUsage?
}

/// Model-scoped weekly limit from the newer `limits` array in the usage API
/// (replaces the legacy `seven_day_opus` / `seven_day_sonnet` fields, which
/// the API now returns as null).
public struct ModelLimit: Sendable {
    public let modelName: String
    public let utilization: Double
    public let resetsAt: Date?
}

public struct UsageWindow: Sendable {
    public let utilization: Double
    public let resetsAt: Date?
}

public struct ExtraUsage: Sendable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?
}

public struct ProfileData: Sendable {
    public let name: String
    public let email: String
    public let planType: String      // "claude_max", "claude_pro", etc.
    public let planDisplayName: String // "Claude Max", "Claude Pro"
    public let subscriptionStatus: String
    public let rateLimitTier: String
    public let memberSince: Date?
}

// MARK: - API Client

public enum UsageAPIClient {
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let cacheFile = URL(fileURLWithPath: "/tmp/claude/maitrics-usage-cache.json")
    private static let profileCacheFile = URL(fileURLWithPath: "/tmp/claude/maitrics-profile-cache.json")
    /// Less than the 60s refresh interval, so each scheduled refresh gets new data.
    private static let cacheTTL: TimeInterval = 45
    private static let profileCacheTTL: TimeInterval = 3600 // 1 hour for profile

    // MARK: - Public

    /// `error` is the state of this fetch. It is `nil` when the data is new or comes from a cache that is not expired.
    public static func fetchUsage() async -> (usage: UsageData?, error: APIError?) {
        if let cached = readCache() { return (cached, nil) }

        let token: String
        switch resolveOAuthToken() {
        case .missing: return (nil, nil)
        // The API answers an expired token with 429, not 401, so it must never be sent.
        case .expired: return (readCache(ignoreExpiry: true), .unauthorized)
        case .valid(let value): token = value
        }

        if let rateLimited, rateLimited.token == token, Date() < rateLimited.until {
            return (readCache(ignoreExpiry: true), .rateLimited(until: rateLimited.until))
        }

        do {
            let data = try await apiRequest(url: usageEndpoint, token: token)
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile)
            return (parseUsageResponse(data), nil)
        } catch let error as APIError {
            return (readCache(ignoreExpiry: true), error)
        } catch {
            return (readCache(ignoreExpiry: true), .networkError(error.localizedDescription))
        }
    }

    public static func fetchProfile() async -> ProfileData? {
        // Check cache first (profile changes rarely)
        if let cached = readProfileCache() { return cached }

        let token: String
        switch resolveOAuthToken() {
        case .missing: return nil
        case .expired: return readProfileCache(ignoreExpiry: true)
        case .valid(let value): token = value
        }

        do {
            let data = try await apiRequest(url: profileEndpoint, token: token)
            try? FileManager.default.createDirectory(at: profileCacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: profileCacheFile)
            return parseProfileResponse(data)
        } catch {
            return readProfileCache(ignoreExpiry: true)
        }
    }

    // MARK: - HTTP

    public enum APIError: Error, Sendable {
        case rateLimited(until: Date)
        case unauthorized
        case serverError(Int)
        case networkError(String)
    }

    /// Keyed by token so a re-login is not held back by the old token's backoff.
    private static var rateLimited: (until: Date, token: String)?

    /// `timeoutInterval` alone only caps *inactivity*, so a server that drips a
    /// byte at a time can keep a request alive indefinitely. The resource timeout
    /// is the wall-clock cap that actually bounds the call.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    private static func apiRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("maitrics/0.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError("No response")
        }

        switch http.statusCode {
        case 200:
            return data
        case 401:
            throw APIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            let until = Date().addingTimeInterval(TimeInterval(retryAfter ?? 300))
            rateLimited = (until, token)
            throw APIError.rateLimited(until: until)
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    /// Whether Claude Code credentials exist at all, expired or not (for UI to show connect state)
    public static var hasToken: Bool {
        resolveOAuthToken() != .missing
    }

    // MARK: - OAuth Token Resolution (via `security` CLI — no keychain prompt)

    public enum OAuthTokenState: Equatable, Sendable {
        case valid(String)
        case expired
        case missing
    }

    private static let keychainService = "Claude Code-credentials"

    static func resolveOAuthToken() -> OAuthTokenState {
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            return .valid(envToken)
        }

        var blobs = readFromKeychainCLI()
        if let fileBlob = FileManager.default.contents(atPath: NSHomeDirectory() + "/.claude/.credentials.json") {
            blobs.append(fileBlob)
        }
        return selectToken(fromCredentials: blobs, now: Date())
    }

    /// Several entries can share the service name (e.g. one left behind by an
    /// older Claude Code under another account), so the first match may be a
    /// token Claude Code no longer refreshes. Picks the unexpired one that
    /// lives longest.
    static func selectToken(fromCredentials blobs: [Data], now: Date) -> OAuthTokenState {
        var sawExpired = false
        var best: (token: String, expiresAt: Date)?

        for blob in blobs {
            guard let json = try? JSONSerialization.jsonObject(with: blob) as? [String: Any],
                  let oauth = json["claudeAiOauth"] as? [String: Any],
                  let token = oauth["accessToken"] as? String,
                  !token.isEmpty else { continue }

            let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? .distantFuture
            if expiresAt <= now {
                sawExpired = true
                continue
            }
            if best == nil || expiresAt > best!.expiresAt {
                best = (token, expiresAt)
            }
        }

        if let best { return .valid(best.token) }
        return sawExpired ? .expired : .missing
    }

    /// Uses `security find-generic-password` CLI tool — same as statusline.sh.
    /// This avoids the keychain password prompt that SecItemCopyMatching triggers
    /// when it reads the secret; listing the account attributes alone does not.
    private static func readFromKeychainCLI() -> [Data] {
        var argumentSets = keychainAccounts().map { ["-a", $0] }
        argumentSets.append([])
        return argumentSets.compactMap { account in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", keychainService] + account + ["-w"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch { return nil }

            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return data.isEmpty ? nil : data
        }
    }

    private static func keychainAccounts() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Cache

    private static func readCache(ignoreExpiry: Bool = false) -> UsageData? {
        guard FileManager.default.fileExists(atPath: cacheFile.path) else { return nil }

        if !ignoreExpiry {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
                  let mtime = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(mtime) < cacheTTL else { return nil }
        }

        guard let data = try? Data(contentsOf: cacheFile) else { return nil }
        return parseUsageResponse(data)
    }

    // MARK: - Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The API sends microsecond fractions (e.g. "…59.842378+00:00"), which
    /// ISO8601DateFormatter rejects (it expects exactly 3 fractional digits).
    private static let microsecondFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return f
    }()

    static func parseAPIDate(_ string: String) -> Date? {
        isoFormatter.date(from: string)
            ?? isoFormatterNoFrac.date(from: string)
            ?? microsecondFormatter.date(from: string)
    }

    private static func parseUsageResponse(_ data: Data) -> UsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHourJSON = json["five_hour"] as? [String: Any],
              let sevenDayJSON = json["seven_day"] as? [String: Any] else { return nil }

        let sevenDaySonnet = (json["seven_day_sonnet"] as? [String: Any]).map { parseWindow($0) }
        let sevenDayOpus = (json["seven_day_opus"] as? [String: Any]).map { parseWindow($0) }

        // Newer API shape: model-scoped weekly limits live in the `limits` array
        var modelLimits: [ModelLimit] = []
        if let limitsJSON = json["limits"] as? [[String: Any]] {
            for limit in limitsJSON {
                guard limit["kind"] as? String == "weekly_scoped",
                      let scope = limit["scope"] as? [String: Any],
                      let model = scope["model"] as? [String: Any] else { continue }
                let name = (model["display_name"] as? String)
                    ?? (model["id"] as? String)
                    ?? "Model"
                let percent = (limit["percent"] as? Double) ?? Double(limit["percent"] as? Int ?? 0)
                let resetsAt = (limit["resets_at"] as? String).flatMap(parseAPIDate)
                modelLimits.append(ModelLimit(modelName: name, utilization: percent, resetsAt: resetsAt))
            }
        }

        var extraUsage: ExtraUsage?
        if let extraJSON = json["extra_usage"] as? [String: Any] {
            extraUsage = ExtraUsage(
                isEnabled: extraJSON["is_enabled"] as? Bool ?? false,
                monthlyLimit: extraJSON["monthly_limit"] as? Double,
                usedCredits: extraJSON["used_credits"] as? Double,
                utilization: extraJSON["utilization"] as? Double
            )
        }

        return UsageData(
            fiveHour: parseWindow(fiveHourJSON),
            sevenDay: parseWindow(sevenDayJSON),
            sevenDaySonnet: sevenDaySonnet,
            sevenDayOpus: sevenDayOpus,
            modelLimits: modelLimits,
            extraUsage: extraUsage
        )
    }

    private static func parseWindow(_ json: [String: Any]) -> UsageWindow {
        let utilization = (json["utilization"] as? Double) ?? 0
        let resetsAt = (json["resets_at"] as? String).flatMap(parseAPIDate)
        return UsageWindow(utilization: utilization, resetsAt: resetsAt)
    }

    // MARK: - Profile Cache & Parsing

    private static func readProfileCache(ignoreExpiry: Bool = false) -> ProfileData? {
        guard FileManager.default.fileExists(atPath: profileCacheFile.path) else { return nil }
        if !ignoreExpiry {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: profileCacheFile.path),
                  let mtime = attrs[.modificationDate] as? Date,
                  Date().timeIntervalSince(mtime) < profileCacheTTL else { return nil }
        }
        guard let data = try? Data(contentsOf: profileCacheFile) else { return nil }
        return parseProfileResponse(data)
    }

    private static func parseProfileResponse(_ data: Data) -> ProfileData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["account"] as? [String: Any],
              let org = json["organization"] as? [String: Any] else { return nil }

        let name = account["display_name"] as? String ?? account["full_name"] as? String ?? "User"
        let email = account["email"] as? String ?? ""
        let orgType = org["organization_type"] as? String ?? "unknown"
        let tier = org["rate_limit_tier"] as? String ?? ""
        let status = org["subscription_status"] as? String ?? ""

        let displayName: String
        switch orgType {
        case "claude_max": displayName = "Claude Max"
        case "claude_pro": displayName = "Claude Pro"
        case "claude_team": displayName = "Claude Team"
        case "claude_enterprise": displayName = "Claude Enterprise"
        default: displayName = orgType.replacingOccurrences(of: "_", with: " ").capitalized
        }

        var memberSince: Date?
        if let dateStr = account["created_at"] as? String {
            memberSince = isoFormatter.date(from: dateStr) ?? isoFormatterNoFrac.date(from: dateStr)
        }

        return ProfileData(
            name: name,
            email: email,
            planType: orgType,
            planDisplayName: displayName,
            subscriptionStatus: status,
            rateLimitTier: tier,
            memberSince: memberSince
        )
    }
}
