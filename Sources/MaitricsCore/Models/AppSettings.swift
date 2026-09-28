import Foundation

public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var claudeDataPath: String {
        get { defaults.string(forKey: "claudeDataPath") ?? defaultClaudePath }
        set { defaults.set(newValue, forKey: "claudeDataPath") }
    }

    public var claudeDataURL: URL {
        URL(fileURLWithPath: (claudeDataPath as NSString).expandingTildeInPath)
    }

    public var statsCachePath: URL { claudeDataURL.appendingPathComponent("stats-cache.json") }
    public var projectsPath: URL { claudeDataURL.appendingPathComponent("projects") }

    public var customPricing: [String: PricingTier]? {
        get {
            guard let data = defaults.data(forKey: "customPricing") else { return nil }
            return try? JSONDecoder().decode([String: PricingTier].self, from: data)
        }
        set {
            if let newValue {
                let data = try? JSONEncoder().encode(newValue)
                defaults.set(data, forKey: "customPricing")
            } else { defaults.removeObject(forKey: "customPricing") }
        }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    /// `false`: cost counts input and output tokens only. `true`: API-equivalent cost with cache tokens.
    public var includeCacheInCost: Bool {
        get { defaults.bool(forKey: "includeCacheInCost") }
        set { defaults.set(newValue, forKey: "includeCacheInCost") }
    }

    public var refreshMode: RefreshMode {
        get { defaults.string(forKey: "refreshMode").flatMap(RefreshMode.init(rawValue:)) ?? .adaptive }
        set { defaults.set(newValue.rawValue, forKey: "refreshMode") }
    }

    public var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    public var alertThresholds: [Int] {
        get { (defaults.array(forKey: "alertThresholds") as? [Int])?.sorted() ?? [80, 95] }
        set { defaults.set(Array(Set(newValue)).sorted(), forKey: "alertThresholds") }
    }

    public var notifyOnReset: Bool {
        get { defaults.object(forKey: "notifyOnReset") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyOnReset") }
    }

    public var alertState: UsageAlertState {
        get {
            guard let data = defaults.data(forKey: "alertState"),
                  let state = try? JSONDecoder().decode(UsageAlertState.self, from: data) else { return UsageAlertState() }
            return state
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "alertState") }
    }

    private var defaultClaudePath: String {
        // Use getpwuid to get the real home directory (NSHomeDirectory returns sandbox container when sandboxed)
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return String(cString: home) + "/.claude"
        }
        return NSHomeDirectory() + "/.claude"
    }
}
