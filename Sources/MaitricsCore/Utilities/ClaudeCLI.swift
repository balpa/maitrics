import Foundation

/// Finds and drives the `claude` CLI. Apps launched from Finder get a minimal
/// PATH (/usr/bin:/bin:/usr/sbin:/sbin), so `claude` has to be located by hand.
public enum ClaudeCLI {
    public enum LoginError: Error, Equatable {
        case cliNotFound
        case launchFailed
    }

    static let defaultCandidates: [String] = {
        let home = NSHomeDirectory()
        return [
            home + "/.local/bin/claude",
            home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
    }()

    static func locate(candidates: [String], isExecutable: (String) -> Bool) -> String? {
        candidates.first(where: isExecutable)
    }

    public static var executablePath: String? {
        locate(candidates: defaultCandidates) { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func loginScript(executablePath: String) -> String {
        let quoted = "'" + executablePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "#!/bin/zsh -l\nexec \(quoted) auth login\n"
    }

    /// `claude auth login` is interactive, so it runs in the user's terminal
    /// through a `.command` file instead of a headless child process.
    public static func openLogin() throws {
        try openLogin(
            executablePath: executablePath,
            scriptURL: FileManager.default.temporaryDirectory.appendingPathComponent("maitrics-login.command")
        )
    }

    static func openLogin(executablePath: String?, scriptURL: URL) throws {
        guard let executablePath else { throw LoginError.cliNotFound }

        do {
            try loginScript(executablePath: executablePath).write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        } catch {
            throw LoginError.launchFailed
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [scriptURL.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw LoginError.launchFailed
        }
        guard process.terminationStatus == 0 else { throw LoginError.launchFailed }
    }
}
