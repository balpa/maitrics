import Foundation

public final class AppSettings: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var thresholdGreen: Int {
        get { defaults.object(forKey: "thresholdGreen") as? Int ?? 100_000 }
        set { defaults.set(newValue, forKey: "thresholdGreen") }
    }

    public var thresholdYellow: Int {
        get { defaults.object(forKey: "thresholdYellow") as? Int ?? 500_000 }
        set { defaults.set(newValue, forKey: "thresholdYellow") }
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

    private var defaultClaudePath: String {
        // Use getpwuid to get the real home directory (NSHomeDirectory returns sandbox container when sandboxed)
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return String(cString: home) + "/.claude"
        }
        return NSHomeDirectory() + "/.claude"
    }
}
