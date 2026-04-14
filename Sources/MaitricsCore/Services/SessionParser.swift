import Foundation

public enum SessionParser {
    public static func parseTokenUsage(fileURL: URL) throws -> SessionTokenUsage {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            return SessionTokenUsage(byModel: [:])
        }
        var byModel: [String: ModelTokens] = [:]
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any] else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

            var existing = byModel[model] ?? .zero
            existing.inputTokens += input
            existing.outputTokens += output
            existing.cacheCreationInputTokens += cacheWrite
            existing.cacheReadInputTokens += cacheRead
            byModel[model] = existing
        }
        return SessionTokenUsage(byModel: byModel)
    }
}
