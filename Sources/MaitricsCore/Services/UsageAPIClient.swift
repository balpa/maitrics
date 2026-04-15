import Foundation

// MARK: - Models

public struct UsageData: Sendable {
    public let fiveHour: UsageWindow
    public let sevenDay: UsageWindow
    public let sevenDaySonnet: UsageWindow?
    public let sevenDayOpus: UsageWindow?
    public let extraUsage: ExtraUsage?
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

// MARK: - API Client

public enum UsageAPIClient {
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let cacheFile = URL(fileURLWithPath: "/tmp/claude/maitrics-usage-cache.json")
    private static let cacheTTL: TimeInterval = 60

    // MARK: - Public

    public static func fetchUsage() async -> UsageData? {
        if let cached = readCache() { return cached }

        guard let token = resolveOAuthToken() else { return nil }

        do {
            let data = try await apiRequest(url: usageEndpoint, token: token)
            try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheFile)
            return parseUsageResponse(data)
        } catch {
            return readCache(ignoreExpiry: true)
        }
    }

    // MARK: - HTTP

    private static func apiRequest(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("maitrics/0.1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - OAuth Token Resolution (via `security` CLI — no keychain prompt)

    static func resolveOAuthToken() -> String? {
        if let envToken = ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"],
           !envToken.isEmpty {
            return envToken
        }

        if let keychainToken = readFromKeychainCLI() {
            return keychainToken
        }

        if let fileToken = readFromCredentialsFile() {
            return fileToken
        }

        return nil
    }

    /// Uses `security find-generic-password` CLI tool — same as statusline.sh.
    /// This avoids the keychain password prompt that SecItemCopyMatching triggers.
    private static func readFromKeychainCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let blob = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !blob.isEmpty,
              let jsonData = blob.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
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

    private static func parseUsageResponse(_ data: Data) -> UsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHourJSON = json["five_hour"] as? [String: Any],
              let sevenDayJSON = json["seven_day"] as? [String: Any] else { return nil }

        let sevenDaySonnet = (json["seven_day_sonnet"] as? [String: Any]).map { parseWindow($0) }
        let sevenDayOpus = (json["seven_day_opus"] as? [String: Any]).map { parseWindow($0) }

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
            extraUsage: extraUsage
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
