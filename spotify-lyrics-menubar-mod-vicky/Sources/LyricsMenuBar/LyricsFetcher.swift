import Foundation
import YTMusicLyrics

struct LyricLine {
    let time: Double
    let text: String
}

struct LyricsFetchResult {
    let lines: [LyricLine]
    let isSynced: Bool
    let source: String?
}

enum LyricsFetchPhase {
    case fetching
    case searching
    case fetchingYTMusic
}

private struct LyricsResponse: Decodable {
    let syncedLyrics: String?
    let plainLyrics: String?

    var hasLyrics: Bool {
        !(syncedLyrics?.isEmpty ?? true) || !(plainLyrics?.isEmpty ?? true)
    }
}

struct FetchCandidate {
    let lines: [LyricLine]
    let isSynced: Bool
    let syncedLyrics: String?
    let plainLyrics: String?
    let source: String

    var isEmpty: Bool { lines.isEmpty }
    var lineCount: Int { lines.count }

    static let empty = FetchCandidate(lines: [], isSynced: false, syncedLyrics: nil, plainLyrics: nil, source: "")

    func asFetchResult() -> LyricsFetchResult {
        LyricsFetchResult(lines: lines, isSynced: isSynced, source: source.isEmpty ? nil : source)
    }
}

enum LyricsFetcher {
    private static let lrclibTimeout: TimeInterval = 3
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
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
    ) -> LyricsFetchResult {
        let (cleanTrack, cleanArtist) = normalize(track: track, artist: artist)

        var cachedPlain: FetchCandidate?
        if !skipCache, let cached = LyricsCache.load(track: cleanTrack, artist: cleanArtist, duration: duration) {
            if cached.1 {
                return LyricsFetchResult(
                    lines: cached.0,
                    isSynced: true,
                    source: LyricsCache.cachedSource(track: cleanTrack, artist: cleanArtist)
                )
            }
            cachedPlain = candidate(from: cached, source: LyricsCache.cachedSource(track: cleanTrack, artist: cleanArtist) ?? "lrclib")
        }

        let lrclib = cachedPlain == nil ? fetchLRCLIB(
            track: cleanTrack,
            artist: cleanArtist,
            duration: duration,
            onPhase: onPhase
        ) : cachedPlain!

        if lrclib.isSynced {
            saveCandidate(lrclib, track: cleanTrack, artist: cleanArtist)
            return lrclib.asFetchResult()
        }

        onPhase?(.fetchingYTMusic)
        let ytm = fetchYTMusic(track: cleanTrack, artist: cleanArtist)
        let final = pickBest(lrclib: lrclib, ytm: ytm)

        if !final.isEmpty {
            saveCandidate(final, track: cleanTrack, artist: cleanArtist)
        }
        return final.asFetchResult()
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

    static func selectEntryWithLyrics(from arr: [[String: Any]]) -> [String: Any]? {
        func nonEmptyString(_ value: Any?) -> Bool {
            if let s = value as? String { return !s.isEmpty }
            return false
        }
        return arr.first { nonEmptyString($0["syncedLyrics"]) || nonEmptyString($0["plainLyrics"]) }
    }

    static func pickBest(lrclib: FetchCandidate, ytm: FetchCandidate?) -> FetchCandidate {
        guard let ytm, !ytm.isEmpty else { return lrclib }
        if ytm.isSynced { return ytm }
        if lrclib.isSynced { return lrclib }
        if lrclib.isEmpty { return ytm }
        return ytm.lineCount >= lrclib.lineCount ? ytm : lrclib
    }

    private static func fetchLRCLIB(
        track: String,
        artist: String,
        duration: Double,
        onPhase: ((LyricsFetchPhase) -> Void)?
    ) -> FetchCandidate {
        let deadline = Date().addingTimeInterval(lrclibTimeout)
        let trackEnc = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track
        let artistEnc = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? artist

        onPhase?(.fetching)
        let directURL = URL(string: "https://lrclib.net/api/get?track_name=\(trackEnc)&artist_name=\(artistEnc)&duration=\(Int(duration))")!
        var payload = fetchWithinDeadline(url: directURL, deadline: deadline)

        if payload == nil, Date() < deadline {
            onPhase?(.searching)
            let searchURL = URL(string: "https://lrclib.net/api/search?track_name=\(trackEnc)&artist_name=\(artistEnc)")!
            if let searchData = fetchWithinDeadline(url: searchURL, deadline: deadline),
               let arr = try? JSONSerialization.jsonObject(with: searchData) as? [[String: Any]],
               let entry = selectEntryWithLyrics(from: arr),
               let entryData = try? JSONSerialization.data(withJSONObject: entry) {
                payload = entryData
            }
        }

        guard let data = payload,
              let response = try? JSONDecoder().decode(LyricsResponse.self, from: data),
              response.hasLyrics else {
            return .empty
        }

        let (lines, isSynced) = lines(from: response, duration: duration)
        return FetchCandidate(
            lines: lines,
            isSynced: isSynced,
            syncedLyrics: response.syncedLyrics,
            plainLyrics: response.plainLyrics,
            source: "lrclib"
        )
    }

    private static func fetchWithinDeadline(url: URL, deadline: Date) -> Data? {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        switch fetchOnce(url: url, timeout: remaining) {
        case .success(let data): return data
        case .httpError, .transient: return nil
        }
    }

    private static func fetchYTMusic(track: String, artist: String) -> FetchCandidate? {
        guard let result = YTMusicLyricsFetcher.fetch(track: track, artist: artist) else { return nil }
        let lines = result.lines.map { LyricLine(time: $0.time, text: $0.text) }
        return FetchCandidate(
            lines: lines,
            isSynced: result.isSynced,
            syncedLyrics: result.syncedLRC,
            plainLyrics: result.plainText,
            source: "ytmusic"
        )
    }

    private static func candidate(from cached: ([LyricLine], Bool), source: String) -> FetchCandidate {
        let plainText = cached.1 ? nil : cached.0.map(\.text).joined(separator: "\n")
        return FetchCandidate(
            lines: cached.0,
            isSynced: cached.1,
            syncedLyrics: cached.1 ? linesToLRC(cached.0) : nil,
            plainLyrics: plainText,
            source: source
        )
    }

    private static func saveCandidate(_ candidate: FetchCandidate, track: String, artist: String) {
        LyricsCache.save(
            track: track,
            artist: artist,
            syncedLyrics: candidate.syncedLyrics,
            plainLyrics: candidate.plainLyrics,
            source: candidate.source
        )
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

    static func linesToLRC(_ lines: [LyricLine]) -> String {
        lines.map { line in
            let total = line.time
            let minutes = Int(total) / 60
            let seconds = total - Double(minutes * 60)
            return String(format: "[%02d:%05.2f] %@", minutes, seconds, line.text)
        }.joined(separator: "\n")
    }

    private static func fetchOnce(url: URL, timeout: TimeInterval) -> FetchOutcome {
        var request = URLRequest(url: url)
        request.timeoutInterval = max(0.1, timeout)
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
        if semaphore.wait(timeout: .now() + timeout + 0.5) == .timedOut {
            task.cancel()
            return .transient
        }
        return outcome
    }

    static func parseLRC(_ text: String) -> [LyricLine] {
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
