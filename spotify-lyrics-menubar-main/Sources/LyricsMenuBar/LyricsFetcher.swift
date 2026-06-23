import Foundation

struct LyricLine {
    let time: Double
    let text: String
}

enum LyricsFetchPhase {
    case fetching
    case searching
}

private struct LyricsResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?

    var hasLyrics: Bool {
        !(syncedLyrics?.isEmpty ?? true) || !(plainLyrics?.isEmpty ?? true)
    }
}

enum LyricsFetcher {
    private static let requestTimeout: TimeInterval = 15
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        return URLSession(configuration: config)
    }()

    private enum FetchOutcome {
        case success(Data)
        case httpError(Int)
        case transient
    }

    private static let lrcRegex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+\.?\d*)\](.*)"#)

    static func normalize(track: String, artist: String) -> (track: String, artist: String) {
        let cleanTrack = track
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let cleanArtist = (artist.components(separatedBy: ",").first ?? artist)
            .trimmingCharacters(in: .whitespaces)
        return (cleanTrack, cleanArtist)
    }

    static func fetch(
        track: String,
        artist: String,
        duration: Double,
        skipCache: Bool = false,
        onPhase: ((LyricsFetchPhase) -> Void)? = nil
    ) -> ([LyricLine], Bool) {
        let (cleanTrack, cleanArtist) = normalize(track: track, artist: artist)

        if !skipCache, let cached = LyricsCache.load(track: cleanTrack, artist: cleanArtist, duration: duration) {
            return cached
        }

        let trackEnc = cleanTrack.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanTrack
        let artistEnc = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanArtist

        onPhase?(.fetching)
        let directURL = URL(string: "https://lrclib.net/api/get?track_name=\(trackEnc)&artist_name=\(artistEnc)&duration=\(Int(duration))")!
        var payload = fetchSync(url: directURL)

        if payload == nil {
            onPhase?(.searching)
            let searchURL = URL(string: "https://lrclib.net/api/search?track_name=\(trackEnc)&artist_name=\(artistEnc)")!
            if let searchData = fetchSync(url: searchURL),
               let arr = try? JSONSerialization.jsonObject(with: searchData) as? [[String: Any]],
               let entry = selectEntryWithLyrics(from: arr),
               let entryData = try? JSONSerialization.data(withJSONObject: entry) {
                payload = entryData
            }
        }

        guard let data = payload,
              let response = try? JSONDecoder().decode(LyricsResponse.self, from: data),
              response.hasLyrics else {
            return ([], false)
        }

        let result = lines(from: response, duration: duration)
        if !result.0.isEmpty {
            LyricsCache.save(
                track: cleanTrack,
                artist: cleanArtist,
                syncedLyrics: response.syncedLyrics,
                plainLyrics: response.plainLyrics
            )
        }
        return result
    }

    static func lines(from entry: CacheEntry, duration: Double) -> ([LyricLine], Bool)? {
        if let synced = entry.syncedLyrics, !synced.isEmpty {
            let parsed = parseLRC(synced)
            return parsed.isEmpty ? nil : (parsed, true)
        }
        if let plain = entry.plainLyrics, !plain.isEmpty {
            let parsed = parsePlainLines(plain)
            return parsed.isEmpty ? nil : (parsed, false)
        }
        return nil
    }

    private static func lines(from response: LyricsResponse, duration: Double) -> ([LyricLine], Bool) {
        if let synced = response.syncedLyrics, !synced.isEmpty {
            return (parseLRC(synced), true)
        }
        if let plain = response.plainLyrics, !plain.isEmpty {
            return (parsePlainLines(plain), false)
        }
        return ([], false)
    }

    private static func parsePlainLines(_ plain: String) -> [LyricLine] {
        plain
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { LyricLine(time: 0, text: $0) }
    }

    static func selectEntryWithLyrics(from arr: [[String: Any]]) -> [String: Any]? {
        func nonEmptyString(_ value: Any?) -> Bool {
            if let s = value as? String { return !s.isEmpty }
            return false
        }
        return arr.first { nonEmptyString($0["syncedLyrics"]) || nonEmptyString($0["plainLyrics"]) }
    }

    private static func fetchSync(url: URL) -> Data? {
        for _ in 1...2 {
            switch fetchOnce(url: url) {
            case .success(let data): return data
            case .httpError: return nil
            case .transient: continue
            }
        }
        return nil
    }

    private static func fetchOnce(url: URL) -> FetchOutcome {
        var request = URLRequest(url: url)
        request.setValue("LyricsMenuBar v2.0 (personal use)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: FetchOutcome = .transient
        let task = session.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200, let data = data {
                    outcome = .success(data)
                } else {
                    outcome = .httpError(http.statusCode)
                }
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + requestTimeout + 1) == .timedOut {
            task.cancel()
            return .transient
        }
        return outcome
    }

    private static func parseLRC(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            let range = NSRange(s.startIndex..., in: s)
            guard let match = lrcRegex.firstMatch(in: s, range: range) else { continue }
            let ns = s as NSString
            let minutes = ns.substring(with: match.range(at: 1))
            let seconds = ns.substring(with: match.range(at: 2))
            let body = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty,
                  let m = Double(minutes),
                  let sec = Double(seconds) else { continue }
            result.append(LyricLine(time: m * 60 + sec, text: body))
        }
        return result.sorted { $0.time < $1.time }
    }
}
