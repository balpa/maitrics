import Foundation

public enum SessionParser {

    /// One assistant message's token accounting, as it appears on a single JSONL line.
    public struct AssistantUsage: Sendable {
        public let model: String
        public let tokens: ModelTokens
        public let timestamp: String?
        /// `message.id` + `requestId`. Claude Code writes one line for each content block of a message.
        /// All these lines have the same key. Only the last line has the final usage.
        public let messageKey: String?
    }

    /// The single decoder for the assistant-line shape. Both the whole-file parse
    /// below and `JSONLUsageIndex`'s incremental scan go through here, so the
    /// transcript schema is only known in one place.
    public static func parseAssistantUsage(line: Data) -> AssistantUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let message = obj["message"] as? [String: Any],
              let model = message["model"] as? String,
              let usage = message["usage"] as? [String: Any] else { return nil }

        return AssistantUsage(
            model: model,
            tokens: ModelTokens(
                inputTokens: usage["input_tokens"] as? Int ?? 0,
                outputTokens: usage["output_tokens"] as? Int ?? 0,
                cacheReadInputTokens: usage["cache_read_input_tokens"] as? Int ?? 0,
                cacheCreationInputTokens: usage["cache_creation_input_tokens"] as? Int ?? 0
            ),
            timestamp: obj["timestamp"] as? String,
            messageKey: (message["id"] as? String).map { "\($0):\(obj["requestId"] as? String ?? "")" }
        )
    }

    public static func parseTokenUsage(fileURL: URL) throws -> SessionTokenUsage {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            return SessionTokenUsage(byModel: [:])
        }
        var byModel: [String: ModelTokens] = [:]
        var previous: AssistantUsage?
        for line in text.components(separatedBy: .newlines) where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let parsed = parseAssistantUsage(line: lineData) else { continue }

            var existing = byModel[parsed.model] ?? .zero
            if let previous, let key = parsed.messageKey, key == previous.messageKey, previous.model == parsed.model {
                existing.inputTokens -= previous.tokens.inputTokens
                existing.outputTokens -= previous.tokens.outputTokens
                existing.cacheCreationInputTokens -= previous.tokens.cacheCreationInputTokens
                existing.cacheReadInputTokens -= previous.tokens.cacheReadInputTokens
            }
            previous = parsed
            existing.inputTokens += parsed.tokens.inputTokens
            existing.outputTokens += parsed.tokens.outputTokens
            existing.cacheCreationInputTokens += parsed.tokens.cacheCreationInputTokens
            existing.cacheReadInputTokens += parsed.tokens.cacheReadInputTokens
            byModel[parsed.model] = existing
        }
        return SessionTokenUsage(byModel: byModel)
    }
}
