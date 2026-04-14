import Foundation

public enum StatsCacheParser {
    public static func parse(data: Data) throws -> StatsCache {
        let decoder = JSONDecoder()
        return try decoder.decode(StatsCache.self, from: data)
    }

    public static func parse(fileURL: URL) throws -> StatsCache {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data)
    }
}
