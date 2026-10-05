import Foundation
import Darwin

public enum RefreshMode: String, CaseIterable, Sendable {
    case adaptive
    case oneMinute = "1m"
    case twoMinutes = "2m"
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case manual

    public var label: String {
        switch self {
        case .adaptive: return "Auto"
        case .manual: return "Off"
        default: return rawValue
        }
    }

    public func interval(claudeActive: Bool) -> TimeInterval? {
        switch self {
        case .adaptive: return claudeActive ? RefreshPolicy.activeInterval : RefreshPolicy.idleInterval
        case .oneMinute: return 60
        case .twoMinutes: return 120
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .manual: return nil
        }
    }
}

public enum RefreshPolicy {
    public static let tickInterval: TimeInterval = 30
    public static let activeInterval: TimeInterval = 60
    public static let idleInterval: TimeInterval = 600
    public static let recentActivityWindow: TimeInterval = 300

    /// Half a tick of tolerance. Without it, a 60s interval checked every 30s becomes 90s.
    public static func isDue(interval: TimeInterval?, lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let interval else { return false }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= interval - tickInterval / 2
    }

    public static func isClaudeActive(processRunning: Bool, lastSessionActivity: Date?, now: Date = Date()) -> Bool {
        if processRunning { return true }
        guard let lastSessionActivity else { return false }
        return now.timeIntervalSince(lastSessionActivity) < recentActivityWindow
    }
}

public enum ClaudeProcessDetector {
    public static func isClaudeRunning() -> Bool {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return false }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return false }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(count) where pid > 0 {
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            let name = String(cString: nameBuffer)
            if name == "claude" { return true }
            // The native install names the process by its version (e.g. "2.1.282"). The npm install runs it as `node …/bin/claude`.
            if name == "node" || name.first?.isNumber == true,
               arguments(of: pid).contains(where: isClaudeArgument) { return true }
        }
        return false
    }

    private static func isClaudeArgument(_ arg: String) -> Bool {
        (arg as NSString).lastPathComponent == "claude" || arg.contains("@anthropic-ai/claude-code")
    }

    /// KERN_PROCARGS2 layout: argc, executable path, NUL padding, argv strings.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while index < size, args.count < argc {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
