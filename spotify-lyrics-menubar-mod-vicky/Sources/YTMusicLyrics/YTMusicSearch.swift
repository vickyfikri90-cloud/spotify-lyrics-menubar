import Foundation

struct YTMusicSearchResult {
    let videoId: String
    let title: String
    let artists: [String]
    let durationSeconds: Int?
}

enum YTMusicSearch {
    private static let songsFilterParams = "EgWKAQIIAWoMEA4QChADEAQQCRAF"

    static func searchSongs(query: String, limit: Int = 5) -> [YTMusicSearchResult] {
        var body: [String: Any] = ["query": query]
        body["params"] = songsFilterParams
        guard let response = YTMusicClient.post(endpoint: "search", body: body) else { return [] }

        let items = YTMJSONNav.findObjects(in: response, matching: "musicResponsiveListItemRenderer")
        var results: [YTMusicSearchResult] = []
        for item in items {
            guard let parsed = parseItem(item) else { continue }
            results.append(parsed)
            if results.count >= limit { break }
        }
        return results
    }

    static func selectBestMatch(from results: [YTMusicSearchResult], track: String, artist: String) -> YTMusicSearchResult? {
        guard !results.isEmpty else { return nil }
        let normalizedTrack = normalizeForMatch(track)
        let normalizedArtist = normalizeForMatch(artist)

        if let exact = results.first(where: { result in
            normalizeForMatch(result.title) == normalizedTrack &&
            result.artists.contains(where: { normalizeForMatch($0) == normalizedArtist })
        }) {
            return exact
        }

        if let partial = results.first(where: { result in
            let title = normalizeForMatch(result.title)
            let artistMatch = result.artists.contains { normalizeForMatch($0).contains(normalizedArtist) || normalizedArtist.contains(normalizeForMatch($0)) }
            return artistMatch && (title.contains(normalizedTrack) || normalizedTrack.contains(title))
        }) {
            return partial
        }

        return results.first
    }

    private static func parseItem(_ item: [String: Any]) -> YTMusicSearchResult? {
        let videoId = extractVideoId(from: item)
        guard let videoId, !videoId.isEmpty else { return nil }

        let flexColumns = item["flexColumns"] as? [[String: Any]] ?? []
        let title = textFromFlexColumn(flexColumns, index: 0)
        guard !title.isEmpty else { return nil }

        let subtitle = textFromFlexColumn(flexColumns, index: 1)
        let artists = parseArtists(from: subtitle)
        let durationSeconds = parseDuration(from: item, flexColumns: flexColumns)

        return YTMusicSearchResult(
            videoId: videoId,
            title: title,
            artists: artists,
            durationSeconds: durationSeconds
        )
    }

    private static func extractVideoId(from item: [String: Any]) -> String? {
        let paths: [[YTMJSONNav.PathItem]] = [
            [.key("playButton"), .key("playNavigationEndpoint"), .key("watchEndpoint"), .key("videoId")],
            [.key("overlay"), .key("musicItemThumbnailOverlayRenderer"), .key("content"), .key("musicPlayButtonRenderer"), .key("playNavigationEndpoint"), .key("watchEndpoint"), .key("videoId")],
        ]
        for path in paths {
            if let id = YTMJSONNav.string(item, path: path), !id.isEmpty {
                return id
            }
        }
        return nil
    }

    private static func textFromFlexColumn(_ columns: [[String: Any]], index: Int) -> String {
        guard columns.indices.contains(index),
              let renderer = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
              let text = renderer["text"] as? [String: Any],
              let runs = text["runs"] as? [[String: Any]] else {
            return ""
        }
        return YTMJSONNav.textRuns(runs)
    }

    private static func parseArtists(from subtitle: String) -> [String] {
        subtitle
            .components(separatedBy: "•")
            .first?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private static func parseDuration(from item: [String: Any], flexColumns: [[String: Any]]) -> Int? {
        if flexColumns.count > 2 {
            let extra = textFromFlexColumn(flexColumns, index: 2)
            if let seconds = parseDurationString(extra) {
                return seconds
            }
        }
        if let fixed = item["fixedColumns"] as? [[String: Any]],
           fixed.indices.contains(0),
           let renderer = fixed[0]["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any],
           let text = renderer["text"] as? [String: Any],
           let runs = text["runs"] as? [[String: Any]] {
            return parseDurationString(YTMJSONNav.textRuns(runs))
        }
        return nil
    }

    private static func parseDurationString(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }

    private static func normalizeForMatch(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^\w\s]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
