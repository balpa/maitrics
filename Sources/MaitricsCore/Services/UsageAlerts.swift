import Foundation

public struct TrackedWindow: Sendable, Equatable {
    public let id: String
    public let name: String
    public let utilization: Double
    public let resetsAt: Date?
    public let duration: TimeInterval

    public init(id: String, name: String, utilization: Double, resetsAt: Date?, duration: TimeInterval) {
        self.id = id
        self.name = name
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.duration = duration
    }
}

extension UsageData {
    public var trackedWindows: [TrackedWindow] {
        var windows = [
            TrackedWindow(id: "session", name: "Session", utilization: fiveHour.utilization,
                          resetsAt: fiveHour.resetsAt, duration: UsagePace.sessionWindow),
            TrackedWindow(id: "weekly", name: "Weekly", utilization: sevenDay.utilization,
                          resetsAt: sevenDay.resetsAt, duration: UsagePace.weeklyWindow),
        ]
        for limit in modelLimits {
            windows.append(TrackedWindow(id: "model:\(limit.modelName)", name: "\(limit.modelName) weekly",
                                         utilization: limit.utilization, resetsAt: limit.resetsAt,
                                         duration: UsagePace.weeklyWindow))
        }
        return windows
    }
}

public struct UsageAlert: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case threshold(Int)
        case reset(peak: Double)
    }

    public let window: TrackedWindow
    public let kind: Kind

    public var title: String {
        switch kind {
        case .threshold:
            return String(format: "%@ limit at %.0f%%", window.name, window.utilization)
        case .reset:
            return "\(window.name) limit reset"
        }
    }

    public var body: String {
        switch kind {
        case .threshold:
            var parts: [String] = []
            if let resetsAt = window.resetsAt {
                parts.append("Resets in \(Formatting.timeUntil(resetsAt)).")
            }
            if let pace = UsagePace.compute(utilization: window.utilization, resetsAt: window.resetsAt, window: window.duration),
               let runsOutIn = pace.runsOutIn, runsOutIn > 0 {
                parts.append("At this pace it runs out in \(Formatting.duration(runsOutIn)).")
            }
            return parts.isEmpty ? "Usage is climbing." : parts.joined(separator: " ")
        case .reset(let peak):
            return String(format: "Back to %.0f%% — last window peaked at %.0f%%.", window.utilization, peak)
        }
    }
}

public struct UsageAlertState: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public var resetsAt: Date?
        public var notified: [Int]
        public var peak: Double
    }

    public var windows: [String: Window]

    public init(windows: [String: Window] = [:]) {
        self.windows = windows
    }
}

public enum UsageAlertEvaluator {
    /// `resets_at` can change a small quantity between responses. A larger change is a new window.
    static let resetTolerance: TimeInterval = 30 * 60

    /// Each threshold fires one time per window. If usage crosses many thresholds at once, only the highest fires.
    public static func evaluate(
        _ windows: [TrackedWindow],
        state: inout UsageAlertState,
        thresholds: [Int],
        notifyOnReset: Bool,
        now: Date = Date()
    ) -> [UsageAlert] {
        let sortedThresholds = thresholds.sorted()
        var alerts: [UsageAlert] = []

        // A reset time in the past means the data is a stale cache. Do not use it.
        for window in windows where window.resetsAt.map({ $0 > now }) ?? true {
            var entry: UsageAlertState.Window
            if let previous = state.windows[window.id] {
                if isNewPeriod(previous: previous.resetsAt, current: window.resetsAt) {
                    if notifyOnReset, let lowest = sortedThresholds.first,
                       previous.peak >= Double(lowest), window.utilization < previous.peak {
                        alerts.append(UsageAlert(window: window, kind: .reset(peak: previous.peak)))
                    }
                    entry = .init(resetsAt: window.resetsAt, notified: [], peak: 0)
                } else {
                    entry = previous
                    if window.resetsAt != nil { entry.resetsAt = window.resetsAt }
                }
            } else {
                entry = .init(resetsAt: window.resetsAt, notified: [], peak: 0)
            }

            let crossed = sortedThresholds.filter { Double($0) <= window.utilization && !entry.notified.contains($0) }
            if let highest = crossed.last {
                alerts.append(UsageAlert(window: window, kind: .threshold(highest)))
                entry.notified.append(contentsOf: crossed)
            }
            entry.peak = max(entry.peak, window.utilization)
            state.windows[window.id] = entry
        }
        return alerts
    }

    static func isNewPeriod(previous: Date?, current: Date?) -> Bool {
        switch (previous, current) {
        case (nil, nil): return false
        case let (p?, c?): return abs(c.timeIntervalSince(p)) > resetTolerance
        default: return true
        }
    }
}
