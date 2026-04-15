import Foundation
import Security

public struct UsageData: Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
}

public struct UsageWindow: Sendable {
    public let utilization: Double // 0-100 percentage
    public let resetsAt: Date?
}

public enum UsageAPIClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let cacheFile = URL(fileURLWithPath: "/tmp/claude/maitrics-usage-cache.json")
    private static let cacheTTL: TimeInterval = 60

    // MARK: - Public

    public static func fetchUsage() async -> UsageData? {
        // Check cache first
        if let cached = readCache() {
            return cached
        }

        // Fetch fresh
        guard let token = resolveOAuthToken() else { return nil }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("maitrics/0.1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return readCache(ignoreExpiry: true)
            }

            // Cache the raw response
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile)

            return parseResponse(data)
        } catch {
            return readCache(ignoreExpiry: true)
        }
    }

    // MARK: - OAuth Token Resolution

    static func resolveOAuthToken() -> String? {
        // 1. Environment variable
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            return envToken
        }

        // 2. macOS Keychain
        if let keychainToken = readFromKeychain() {
            return keychainToken
        }

        // 3. Credentials file
        if let fileToken = readFromCredentialsFile() {
            return fileToken
        }

        return nil
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }

        return token
    }

    private static func readFromCredentialsFile() -> String? {
        let path = NSHomeDirectory() + "/.claude/.credentials.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
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
        return parseResponse(data)
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

    private static func parseResponse(_ data: Data) -> UsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let fiveHourJSON = json["five_hour"] as? [String: Any],
              let sevenDayJSON = json["seven_day"] as? [String: Any] else { return nil }

        return UsageData(
            fiveHour: parseWindow(fiveHourJSON),
            sevenDay: parseWindow(sevenDayJSON)
        )
    }

    private static func parseWindow(_ json: [String: Any]) -> UsageWindow {
        let utilization = (json["utilization"] as? Double) ?? 0
        var resetsAt: Date?
        if let resetStr = json["resets_at"] as? String {
            resetsAt = isoFormatter.date(from: resetStr) ?? isoFormatterNoFrac.date(from: resetStr)
        }
        return UsageWindow(utilization: utilization, resetsAt: resetsAt)
    }
}
