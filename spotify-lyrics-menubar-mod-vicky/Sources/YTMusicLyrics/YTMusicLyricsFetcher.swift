import Foundation

public struct YTMusicLyricLine {
    public let time: Double
    public let text: String
}

public struct YTMusicFetchResult {
    public let lines: [YTMusicLyricLine]
    public let isSynced: Bool
    public let syncedLRC: String?
    public let plainText: String?

    public var lineCount: Int { lines.count }
}

public enum YTMusicLyricsFetcher {
    public static func fetch(track: String, artist: String) -> YTMusicFetchResult? {
        let query = "\(artist) \(track)"
        let results = YTMusicSearch.searchSongs(query: query)
        guard let match = YTMusicSearch.selectBestMatch(from: results, track: track, artist: artist) else {
            return nil
        }
        return fetch(videoId: match.videoId)
    }

    static func fetch(videoId: String) -> YTMusicFetchResult? {
        guard let browseId = lyricsBrowseId(for: videoId) else { return nil }
        if let synced = fetchLyrics(browseId: browseId, mobile: true), synced.isSynced {
            return synced
        }
        return fetchLyrics(browseId: browseId, mobile: false)
    }

    private static func lyricsBrowseId(for videoId: String) -> String? {
        let body: [String: Any] = [
            "enablePersistentPlaylistPanel": true,
            "isAudioOnly": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "videoId": videoId,
            "playlistId": "RDAMVM" + videoId,
            "watchEndpointMusicSupportedConfigs": [
                "watchEndpointMusicConfig": [
                    "hasPersistentPlaylistPanel": true,
                    "musicVideoType": "MUSIC_VIDEO_TYPE_ATV",
                ],
            ],
        ]
        guard let response = YTMusicClient.post(endpoint: "next", body: body) else { return nil }
        return extractLyricsBrowseId(from: response)
    }

    static func extractLyricsBrowseId(from response: [String: Any]) -> String? {
        let tabs = YTMJSONNav.nav(
            response,
            path: [
                .key("contents"),
                .key("singleColumnMusicWatchNextResultsRenderer"),
                .key("tabbedRenderer"),
                .key("watchNextTabbedResultsRenderer"),
                .key("tabs"),
            ]
        ) as? [[String: Any]] ?? []

        for tab in tabs {
            if let renderer = tab["tabRenderer"] as? [String: Any],
               renderer["unselectable"] != nil {
                continue
            }
            guard let endpoint = YTMJSONNav.dict(tab, path: [.key("tabRenderer"), .key("endpoint"), .key("browseEndpoint")]),
                  let pageType = endpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
                  let musicConfig = pageType["browseEndpointContextMusicConfig"] as? [String: Any],
                  let pageTypeValue = musicConfig["pageType"] as? String,
                  pageTypeValue == "MUSIC_PAGE_TYPE_TRACK_LYRICS",
                  let browseId = endpoint["browseId"] as? String,
                  browseId.hasPrefix("MPLYt") else {
                continue
            }
            return browseId
        }
        return nil
    }

    static func fetchLyrics(browseId: String, mobile: Bool) -> YTMusicFetchResult? {
        guard let response = YTMusicClient.post(endpoint: "browse", body: ["browseId": browseId], mobile: mobile) else {
            return nil
        }

        if mobile, let timed = parseTimedLyrics(from: response) {
            return timed
        }
        return parsePlainLyrics(from: response)
    }

    static func parseTimedLyrics(from response: [String: Any]) -> YTMusicFetchResult? {
        let timedData = YTMJSONNav.nav(
            response,
            path: [
                .key("contents"),
                .key("elementRenderer"),
                .key("newElement"),
                .key("type"),
                .key("componentType"),
                .key("model"),
                .key("timedLyricsModel"),
                .key("lyricsData"),
                .key("timedLyricsData"),
            ]
        ) as? [[String: Any]]

        guard let timedData, !timedData.isEmpty else { return nil }

        var lines: [YTMusicLyricLine] = []
        for raw in timedData {
            guard let text = raw["lyricLine"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let cueRange = raw["cueRange"] as? [String: Any],
                  let startMsString = cueRange["startTimeMilliseconds"] as? String,
                  let startMs = Double(startMsString) else {
                continue
            }
            lines.append(YTMusicLyricLine(time: startMs / 1000.0, text: text))
        }

        guard !lines.isEmpty else { return nil }
        let sorted = lines.sorted { $0.time < $1.time }
        let lrc = linesToLRC(sorted)
        return YTMusicFetchResult(lines: sorted, isSynced: true, syncedLRC: lrc, plainText: nil)
    }

    static func parsePlainLyrics(from response: [String: Any]) -> YTMusicFetchResult? {
        let shelfItems = YTMJSONNav.findObjects(in: response, matching: "musicDescriptionShelfRenderer")
        for shelf in shelfItems {
            if let description = shelf["description"] as? [String: Any],
               let runs = description["runs"] as? [[String: Any]] {
                let text = YTMJSONNav.textRuns(runs).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let lines = text
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .map { YTMusicLyricLine(time: 0, text: $0) }
                    guard !lines.isEmpty else { continue }
                    return YTMusicFetchResult(lines: lines, isSynced: false, syncedLRC: nil, plainText: text)
                }
            }
        }
        return nil
    }

    static func linesToLRC(_ lines: [YTMusicLyricLine]) -> String {
        lines.map { line in
            let total = line.time
            let minutes = Int(total) / 60
            let seconds = total - Double(minutes * 60)
            return String(format: "[%02d:%05.2f] %@", minutes, seconds, line.text)
        }.joined(separator: "\n")
    }
}
