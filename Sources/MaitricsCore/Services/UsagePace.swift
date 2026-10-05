import Foundation

public struct UsagePace: Sendable, Equatable {
    /// Utilization at an even burn rate at this time (0–100).
    public let expectedPercent: Double
    /// Actual minus expected. Positive means usage is too fast.
    public let delta: Double
    /// `nil`: the window resets first. `0`: the limit is reached.
    public let runsOutIn: TimeInterval?

    public static let sessionWindow: TimeInterval = 5 * 3600
    public static let weeklyWindow: TimeInterval = 7 * 86400

    /// Before this part of the window, the rate is not reliable. Do not project.
    static let minElapsedFraction = 0.05

    public static let onPaceBand = 5.0

    public static func compute(utilization: Double, resetsAt: Date?, window: TimeInterval, now: Date = Date()) -> UsagePace? {
        guard let resetsAt, window > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0, remaining <= window else { return nil }

        let elapsed = window - remaining
        let fraction = elapsed / window
        let expected = fraction * 100
        let delta = utilization - expected

        var runsOutIn: TimeInterval?
        if utilization >= 100 {
            runsOutIn = 0
        } else if utilization > 0, fraction >= minElapsedFraction {
            let ratePerSecond = utilization / elapsed
            let timeTo100 = (100 - utilization) / ratePerSecond
            if timeTo100 < remaining { runsOutIn = timeTo100 }
        }
        return UsagePace(expectedPercent: expected, delta: delta, runsOutIn: runsOutIn)
    }

    public var isAhead: Bool { delta > Self.onPaceBand }
    public var isBehind: Bool { delta < -Self.onPaceBand }

    public var summary: String {
        var parts: [String] = []
        if isAhead {
            parts.append(String(format: "%.0f%% ahead of pace", delta))
        } else if isBehind {
            parts.append(String(format: "%.0f%% under pace", -delta))
        } else {
            parts.append("On pace")
        }
        if let runsOutIn {
            parts.append(runsOutIn <= 0 ? "limit reached" : "runs out in \(Formatting.duration(runsOutIn))")
        }
        return parts.joined(separator: " · ")
    }
}
