import Foundation

public struct SessionIndex: Codable, Sendable {
    public let version: Int
    public let entries: [SessionIndexEntry]
    public let originalPath: String?
}

public struct SessionIndexEntry: Codable, Sendable {
    public let sessionId: String
    public let fullPath: String
    public let fileMtime: Int64?
    public let firstPrompt: String
    public let messageCount: Int
    public let created: String
    public let modified: String
    public let gitBranch: String?
    public let projectPath: String?
    public let isSidechain: Bool?
}

/// Unified session info returned by discovery — from either index or JSONL scan
public struct DiscoveredSession: Sendable {
    public let sessionId: String
    public let firstPrompt: String
    public let messageCount: Int
    public let created: Date
    public let modified: Date
    public let gitBranch: String?
    public let projectPath: String?
    public let projectName: String
    public let jsonlPath: String?
}
