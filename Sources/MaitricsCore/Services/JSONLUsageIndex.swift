import Foundation

/// Incremental, persistent index over Claude Code's session JSONL files.
///
/// Session transcripts are append-only and can reach hundreds of megabytes in
/// total, so re-reading and JSON-decoding them on every refresh is what made
/// the app burn a full core for ~15s per file-watch event. This index remembers
/// how many bytes of each file it has already accounted for and only parses the
/// bytes appended since then. The tallies are persisted so a relaunch doesn't
/// start from zero either.
public final class JSONLUsageIndex: @unchecked Sendable {

    /// Per-model tallies. The property names follow the repo's other token models;
    /// the coding keys stay short so the on-disk cache stays small.
    struct Tokens: Codable, Equatable {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheCreationInputTokens: Int = 0
        var cacheReadInputTokens: Int = 0

        enum CodingKeys: String, CodingKey {
            case inputTokens = "i"
            case outputTokens = "o"
            case cacheCreationInputTokens = "cw"
            case cacheReadInputTokens = "cr"
        }
    }

    struct Entry: Codable, Equatable {
        /// File size at the time of the last scan — the append detector.
        var size: Int64 = 0
        /// Byte offset up to which complete lines have been accounted for.
        var offset: Int64 = 0
        var byModel: [String: Tokens] = [:]
        /// date (yyyy-MM-dd, local) -> model -> full token breakdown
        var byDayModel: [String: [String: Tokens]] = [:]
        /// hour (yyyy-MM-dd HH, local) -> model -> full token breakdown
        var byHourModel: [String: [String: Tokens]] = [:]
        /// The last counted message. A line with the same key replaces it.
        var lastMessage: CountedMessage?
    }

    struct CountedMessage: Codable, Equatable {
        var key: String
        var model: String
        var hour: String?
        var tokens: Tokens
    }

    private struct Cache: Codable {
        var version: Int
        var entries: [String: Entry]
    }

    // v2: byDayModel switched from a bare input+output Int to the full Tokens
    // breakdown, so cost (not just token count) can be estimated for days the
    // stats cache hasn't covered yet. Older caches simply get discarded and
    // rebuilt from the still-present JSONL files.
    // v3: adds byHourModel for the hourly trend.
    // v4: counts each message one time. Before, each content block line of a message was counted.
    private static let cacheVersion = 4

    private let cacheURL: URL
    private let chunkSize: Int
    private let dayFormatter: DateFormatter
    private let hourFormatter: DateFormatter
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var dirty = false

    public convenience init(cacheURL: URL? = nil) {
        self.init(cacheURL: cacheURL, chunkSize: 4 << 20)
    }

    /// `chunkSize` and `timeZone` are only overridden by tests, to exercise the
    /// multi-chunk path and the fractional-offset day boundaries.
    init(cacheURL: URL?, chunkSize: Int, timeZone: TimeZone = .current) {
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
        self.chunkSize = chunkSize
        self.dayFormatter = Self.makeDayFormatter(timeZone: timeZone)
        self.hourFormatter = Self.makeHourFormatter(timeZone: timeZone)
        load()
    }

    static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("Maitrics/usage-index.json")
    }

    // MARK: - Public API

    /// Full per-model token usage for one session file.
    public func tokenUsage(forPath path: String) -> SessionTokenUsage? {
        guard let entry = entry(forPath: path) else { return nil }
        var byModel: [String: ModelTokens] = [:]
        for (model, t) in entry.byModel {
            byModel[model] = ModelTokens(
                inputTokens: t.inputTokens,
                outputTokens: t.outputTokens,
                cacheReadInputTokens: t.cacheReadInputTokens,
                cacheCreationInputTokens: t.cacheCreationInputTokens
            )
        }
        return SessionTokenUsage(byModel: byModel)
    }

    public func fileUsage(forPath path: String) -> FileUsage? {
        guard let entry = entry(forPath: path) else { return nil }
        return FileUsage(byDay: entry.byDayModel.mapValues(Self.modelTokens),
                         byHour: entry.byHourModel.mapValues(Self.modelTokens))
    }

    public struct FileUsage: Sendable {
        public let byDay: [String: [String: ModelTokens]]
        public let byHour: [String: [String: ModelTokens]]
    }

    private static func modelTokens(_ models: [String: Tokens]) -> [String: ModelTokens] {
        models.mapValues {
            ModelTokens(inputTokens: $0.inputTokens, outputTokens: $0.outputTokens,
                        cacheReadInputTokens: $0.cacheReadInputTokens,
                        cacheCreationInputTokens: $0.cacheCreationInputTokens)
        }
    }

    /// Merged `date -> model -> input+output` totals for the given session files,
    /// restricted to days strictly after `cutoff`.
    public func dailyTokens(forPaths paths: [String], after cutoff: Date) -> [String: [String: Int]] {
        let formatter = dayFormatter
        var merged: [String: [String: Int]] = [:]
        for path in paths {
            guard let entry = entry(forPath: path) else { continue }
            for (day, models) in entry.byDayModel {
                guard let dayDate = formatter.date(from: day), dayDate > cutoff else { continue }
                for (model, tokens) in models {
                    merged[day, default: [:]][model, default: 0] += tokens.inputTokens + tokens.outputTokens
                }
            }
        }
        return merged
    }

    /// Merged `date -> model -> full token breakdown` for the given session
    /// files, restricted to days strictly after `cutoff`. Unlike `dailyTokens`,
    /// this keeps input/output/cache split apart so cost can be estimated
    /// directly instead of guessed from an aggregate ratio.
    public func dailyModelUsage(forPaths paths: [String], after cutoff: Date) -> [String: [String: ModelTokens]] {
        let formatter = dayFormatter
        var merged: [String: [String: ModelTokens]] = [:]
        for path in paths {
            guard let entry = entry(forPath: path) else { continue }
            for (day, models) in entry.byDayModel {
                guard let dayDate = formatter.date(from: day), dayDate > cutoff else { continue }
                for (model, tokens) in models {
                    var acc = merged[day]?[model] ?? .zero
                    acc.inputTokens += tokens.inputTokens
                    acc.outputTokens += tokens.outputTokens
                    acc.cacheReadInputTokens += tokens.cacheReadInputTokens
                    acc.cacheCreationInputTokens += tokens.cacheCreationInputTokens
                    merged[day, default: [:]][model] = acc
                }
            }
        }
        return merged
    }

    /// Writes the cache back to disk if anything changed. Cheap no-op otherwise.
    public func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = Cache(version: Self.cacheVersion, entries: entries)
        dirty = false
        lock.unlock()

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Drops cached entries for files that no longer exist.
    public func prune(keeping livePaths: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        let before = entries.count
        entries = entries.filter { livePaths.contains($0.key) }
        if entries.count != before { dirty = true }
    }

    // MARK: - Scanning

    private func entry(forPath path: String) -> Entry? {
        guard let size = Self.fileSize(path) else { return nil }

        lock.lock()
        var entry = entries[path] ?? Entry()
        lock.unlock()

        if entry.size == size && entry.offset > 0 {
            return entry  // nothing appended since the last scan
        }
        if size < entry.size {
            entry = Entry()  // file shrank — it was rewritten, start over
        }

        // Any failure to reach the new bytes leaves the previously stored tally in
        // place: it is the last known-good answer, and marking the file as fully
        // accounted for would freeze an undercount instead.
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return storedEntry(forPath: path)
        }
        defer { try? handle.close() }
        if entry.offset > 0 {
            guard (try? handle.seek(toOffset: UInt64(entry.offset))) != nil else {
                return storedEntry(forPath: path)
            }
        }

        var leftover = Data()
        var offset = entry.offset
        var tally = Tally(formatter: hourFormatter, byModel: entry.byModel,
                          byDayModel: entry.byDayModel, byHourModel: entry.byHourModel,
                          lastMessage: entry.lastMessage)

        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: chunkSize)
            } catch {
                // A read error is not end-of-file — abandon the scan rather than
                // persisting `size` next to a partial `offset`.
                return storedEntry(forPath: path)
            }
            guard let chunk, !chunk.isEmpty else { break }

            var buffer: Data
            if leftover.isEmpty {
                buffer = chunk
            } else {
                buffer = leftover
                buffer.append(chunk)
            }
            // `buffer` starts at file position `offset`, so consumed bytes of
            // complete lines advance the offset directly — the carried-over
            // partial line is already part of that span.
            let consumed = Self.consumeLines(buffer, into: &tally)
            offset += Int64(consumed)
            leftover = consumed < buffer.count ? Data(buffer[(buffer.startIndex + consumed)...]) : Data()
        }

        // `size` was stat'd before the read, so a transcript appended to during
        // the scan can leave `offset` past it. Recording the high-water mark keeps
        // the shrink detector honest — otherwise a later truncation to a length
        // between the two would seek past EOF forever and lose those bytes.
        entry.size = max(size, offset)
        entry.offset = offset
        entry.byModel = tally.byModel
        entry.byDayModel = tally.byDayModel
        entry.byHourModel = tally.byHourModel
        entry.lastMessage = tally.lastMessage

        lock.lock()
        let changed = entries[path] != entry
        entries[path] = entry
        // An empty or newline-less transcript re-scans on every refresh; marking
        // the index dirty regardless would rewrite the whole cache file each time.
        if changed { dirty = true }
        lock.unlock()

        return entry
    }

    private func storedEntry(forPath path: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[path]
    }

    /// Running totals plus a one-slot memo for timestamp -> local hour conversion.
    private struct Tally {
        let formatter: DateFormatter
        var byModel: [String: Tokens]
        var byDayModel: [String: [String: Tokens]]
        var byHourModel: [String: [String: Tokens]]
        var lastMessage: CountedMessage?
        var memoKey: String = ""
        var memoHour: String = ""
    }

    /// Splits `buffer` on newlines, folds every assistant message into `tally`,
    /// and returns how many bytes of complete lines were consumed.
    private static func consumeLines(_ buffer: Data, into tally: inout Tally) -> Int {
        var consumed = 0
        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = raw.count
            var start = 0
            while start < count {
                guard let nl = memchr(base + start, 0x0A, count - start) else { break }
                let nlIndex = UnsafeRawPointer(nl) - UnsafeRawPointer(base)
                let length = nlIndex - start
                if length > 0 {
                    consumeLine(base + start, length, into: &tally)
                }
                start = nlIndex + 1
            }
            consumed = start
        }
        return consumed
    }

    /// `"output_tokens"` — every assistant message carries it, so a raw byte
    /// search is a sound pre-filter that skips JSON-decoding the ~90% of bytes
    /// made up of user turns and tool results.
    private static let usageMarker: [UInt8] = Array(#""output_tokens""#.utf8)

    private static func consumeLine(_ ptr: UnsafePointer<UInt8>, _ length: Int, into tally: inout Tally) {
        let found = usageMarker.withUnsafeBufferPointer { marker -> Bool in
            memmem(ptr, length, marker.baseAddress!, marker.count) != nil
        }
        guard found else { return }

        let data = Data(bytes: ptr, count: length)
        guard let parsed = SessionParser.parseAssistantUsage(line: data) else { return }
        let model = parsed.model
        let tokens = Tokens(inputTokens: parsed.tokens.inputTokens, outputTokens: parsed.tokens.outputTokens,
                            cacheCreationInputTokens: parsed.tokens.cacheCreationInputTokens,
                            cacheReadInputTokens: parsed.tokens.cacheReadInputTokens)

        if let last = tally.lastMessage, let key = parsed.messageKey, key == last.key {
            apply(last.tokens, sign: -1, model: last.model, hour: last.hour, to: &tally)
        }

        // A message with no parseable timestamp still counts toward the session
        // total but is deliberately left out of the per-day breakdown: there is no
        // honest day to attribute it to, and daily totals fall back to the stats
        // cache for any day the live scan does not cover.
        var hour: String?
        if let timestamp = parsed.timestamp {
            let h = localHour(for: timestamp, tally: &tally)
            if !h.isEmpty { hour = h }
        }
        apply(tokens, sign: 1, model: model, hour: hour, to: &tally)
        tally.lastMessage = parsed.messageKey.map { CountedMessage(key: $0, model: model, hour: hour, tokens: tokens) }
    }

    private static func apply(_ tokens: Tokens, sign: Int, model: String, hour: String?, to tally: inout Tally) {
        add(tokens, sign: sign, to: &tally.byModel[model, default: Tokens()])
        guard let hour else { return }
        let day = String(hour.prefix(10))
        add(tokens, sign: sign, to: &tally.byDayModel[day, default: [:]][model, default: Tokens()])
        add(tokens, sign: sign, to: &tally.byHourModel[hour, default: [:]][model, default: Tokens()])
    }

    private static func add(_ tokens: Tokens, sign: Int, to total: inout Tokens) {
        total.inputTokens += sign * tokens.inputTokens
        total.outputTokens += sign * tokens.outputTokens
        total.cacheCreationInputTokens += sign * tokens.cacheCreationInputTokens
        total.cacheReadInputTokens += sign * tokens.cacheReadInputTokens
    }

    /// Messages arrive in chronological order, so consecutive lines almost always
    /// share the same UTC minute, and memoizing on the `yyyy-MM-ddTHH:mm` prefix
    /// removes two date formatter round-trips per message.
    ///
    /// The key must be the minute, not the hour: every real UTC offset is a whole
    /// number of minutes, but not of hours (Asia/Kolkata +5:30, Pacific/Chatham
    /// +12:45), so a single UTC *hour* can straddle local midnight and an
    /// hour-keyed memo would book the tokens after midnight to the wrong day.
    private static let memoKeyLength = 16  // "yyyy-MM-ddTHH:mm"

    private static func localHour(for timestamp: String, tally: inout Tally) -> String {
        let key = String(timestamp.prefix(memoKeyLength))
        if key.count == memoKeyLength && key == tally.memoKey { return tally.memoHour }

        let date = SessionDiscovery.parseDate(timestamp)
        guard date != Date.distantPast else { return "" }
        let hour = tally.formatter.string(from: date)
        if key.count == memoKeyLength {
            tally.memoKey = key
            tally.memoHour = hour
        }
        return hour
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == Self.cacheVersion else { return }
        entries = cache.entries
    }

    private static func fileSize(_ path: String) -> Int64? {
        var st = stat()
        guard stat(path, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { return nil }
        return Int64(st.st_size)
    }

    /// The single definition of the `yyyy-MM-dd` day key. `ClaudeDataManager`
    /// reads back the keys this index writes, so both must use exactly this
    /// formatter — hence one factory rather than two look-alike statics.
    public static func makeDayFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }

    /// The first 10 characters of an hour key are its day key.
    public static func makeHourFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }
}
