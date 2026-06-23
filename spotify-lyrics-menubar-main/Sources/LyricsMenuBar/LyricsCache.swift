import Foundation

struct CacheEntry: Codable {
    let track: String
    let artist: String
    let syncedLyrics: String?
    let plainLyrics: String?
}

enum LyricsCache {
    private static let queue = DispatchQueue(label: "lyrics.cache", qos: .utility)
    private static var entries: [String: CacheEntry] = loadFromDisk()

    static var count: Int {
        queue.sync { entries.count }
    }

    static func load(track: String, artist: String, duration: Double) -> ([LyricLine], Bool)? {
        let key = cacheKey(track: track, artist: artist)
        let entry: CacheEntry? = queue.sync { entries[key] }
        guard let entry else { return nil }
        return LyricsFetcher.lines(from: entry, duration: duration)
    }

    static func save(track: String, artist: String, syncedLyrics: String?, plainLyrics: String?) {
        let (cleanTrack, cleanArtist) = LyricsFetcher.normalize(track: track, artist: artist)
        let key = cacheKey(track: cleanTrack, artist: cleanArtist)
        let entry = CacheEntry(
            track: cleanTrack,
            artist: cleanArtist,
            syncedLyrics: syncedLyrics,
            plainLyrics: plainLyrics
        )
        queue.sync {
            entries[key] = entry
            saveToDisk(entries)
        }
    }

    static func removeAll() {
        queue.sync {
            entries.removeAll()
            saveToDisk(entries)
        }
    }

    static func cacheKey(track: String, artist: String) -> String {
        let (cleanTrack, cleanArtist) = LyricsFetcher.normalize(track: track, artist: artist)
        return "\(cleanArtist.lowercased())|\(cleanTrack.lowercased())"
    }

    private static var cacheFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LyricsMenuBar/lyrics-cache.json")
    }

    private static func loadFromDisk() -> [String: CacheEntry] {
        let url = cacheFileURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveToDisk(_ entries: [String: CacheEntry]) {
        let url = cacheFileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            // Cache is best-effort; ignore write failures.
        }
    }
}
