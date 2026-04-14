import Foundation

public enum SessionDiscovery {
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

    static func parseDate(_ string: String) -> Date {
        isoFormatter.date(from: string)
            ?? isoFormatterNoFrac.date(from: string)
            ?? Date.distantPast
    }

    public static func parseIndex(data: Data) throws -> SessionIndex {
        try JSONDecoder().decode(SessionIndex.self, from: data)
    }

    public static func projectName(fromEncodedPath encoded: String) -> String {
        let parts = encoded.split(separator: "-", omittingEmptySubsequences: true)
        if let docsIndex = parts.lastIndex(where: { $0 == "Documents" || $0 == "Desktop" || $0 == "repos" || $0 == "projects" || $0 == "code" || $0 == "src" || $0 == "dev" || $0 == "home" }) {
            let remaining = parts[(docsIndex + 1)...]
            if !remaining.isEmpty {
                return remaining.joined(separator: "-")
            }
        }
        return parts.last.map(String.init) ?? encoded
    }

    public static func discoverSessions(claudeProjectsDir: URL) throws -> [DiscoveredSession] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeProjectsDir.path) else { return [] }

        let projectDirs = try fm.contentsOfDirectory(at: claudeProjectsDir, includingPropertiesForKeys: nil)
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

        var sessions: [DiscoveredSession] = []

        for projectDir in projectDirs {
            let encodedName = projectDir.lastPathComponent
            let name = projectName(fromEncodedPath: encodedName)
            let indexFile = projectDir.appendingPathComponent("sessions-index.json")

            if fm.fileExists(atPath: indexFile.path),
               let data = try? Data(contentsOf: indexFile),
               let index = try? parseIndex(data: data) {
                for entry in index.entries where entry.isSidechain != true {
                    sessions.append(DiscoveredSession(
                        sessionId: entry.sessionId,
                        firstPrompt: cleanPrompt(entry.firstPrompt),
                        messageCount: entry.messageCount,
                        created: parseDate(entry.created),
                        modified: parseDate(entry.modified),
                        gitBranch: entry.gitBranch,
                        projectPath: entry.projectPath,
                        projectName: name,
                        jsonlPath: entry.fullPath
                    ))
                }
            } else {
                let jsonlFiles = (try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]))?.filter { $0.pathExtension == "jsonl" } ?? []

                for jsonlFile in jsonlFiles {
                    let sessionId = jsonlFile.deletingPathExtension().lastPathComponent
                    let attrs = try? fm.attributesOfItem(atPath: jsonlFile.path)
                    let modified = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
                    let created = (attrs?[.creationDate] as? Date) ?? modified
                    let prompt = extractFirstPrompt(from: jsonlFile)

                    sessions.append(DiscoveredSession(
                        sessionId: sessionId,
                        firstPrompt: prompt ?? sessionId,
                        messageCount: 0,
                        created: created,
                        modified: modified,
                        gitBranch: nil,
                        projectPath: nil,
                        projectName: name,
                        jsonlPath: jsonlFile.path
                    ))
                }
            }
        }

        sessions.sort { $0.modified > $1.modified }
        return sessions
    }

    private static func cleanPrompt(_ prompt: String) -> String {
        if prompt.hasPrefix("<") {
            if let range = prompt.range(of: "This may or may not be related to the current") {
                let afterTag = prompt[range.upperBound...]
                let trimmed = afterTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "…"))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "IDE session" : trimmed
            }
            return "IDE session"
        }
        if prompt.count > 100 { return String(prompt.prefix(100)) }
        return prompt
    }

    private static func extractFirstPrompt(from jsonlFile: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: jsonlFile) else { return nil }
        defer { handle.closeFile() }
        let chunk = handle.readData(ofLength: 8192)
        guard let text = String(data: chunk, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "user",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? String else { continue }
            return cleanPrompt(content)
        }
        return nil
    }
}
