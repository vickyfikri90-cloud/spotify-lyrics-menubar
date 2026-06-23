import XCTest
@testable import LyricsMenuBar

final class LyricsFetcherTests: XCTestCase {
    private func makeCandidate(
        lines: [LyricLine],
        isSynced: Bool,
        source: String = "lrclib"
    ) -> FetchCandidate {
        let synced = isSynced ? LyricsFetcher.linesToLRC(lines) : nil
        let plain = isSynced ? nil : lines.map(\.text).joined(separator: "\n")
        return FetchCandidate(
            lines: lines,
            isSynced: isSynced,
            syncedLyrics: synced,
            plainLyrics: plain,
            source: source
        )
    }

    func testSearchFallbackReturnsLyricsWhenFirstResultHasNone() {
        let searchBody = """
        [
          {"id":1,"trackName":"The Winner Takes It All","artistName":"ABBA","albumName":"Super Trouper","duration":295,"instrumental":true,"plainLyrics":null,"syncedLyrics":null},
          {"id":2,"trackName":"The Winner Takes It All","artistName":"ABBA","albumName":"Super Trouper","duration":295,"instrumental":false,"plainLyrics":"I don't wanna talk\\nAbout things we've gone through","syncedLyrics":"[00:24.10] I don't wanna talk\\n[00:30.50] About things we've gone through"}
        ]
        """.data(using: .utf8)!

        guard let arr = try? JSONSerialization.jsonObject(with: searchBody) as? [[String: Any]],
              let entry = LyricsFetcher.selectEntryWithLyrics(from: arr),
              let entryData = try? JSONSerialization.data(withJSONObject: entry) else {
            return XCTFail("Failed to parse search payload")
        }

        struct LyricsResponse: Decodable {
            let syncedLyrics: String?
            let plainLyrics: String?
        }

        guard let response = try? JSONDecoder().decode(LyricsResponse.self, from: entryData) else {
            return XCTFail("Failed to decode lyrics response")
        }

        if let synced = response.syncedLyrics, !synced.isEmpty {
            let lines = LyricsFetcher.parseLRC(synced)
            XCTAssertFalse(lines.isEmpty)
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected synced lyrics from search result #2")
        }
    }

    func testPickBestPrefersYTSyncedOverLRCLIBPlain() {
        let lrclib = makeCandidate(
            lines: [LyricLine(time: 0, text: "Plain line")],
            isSynced: false
        )
        let ytm = makeCandidate(
            lines: [LyricLine(time: 10, text: "Synced line")],
            isSynced: true,
            source: "ytmusic"
        )

        let best = LyricsFetcher.pickBest(lrclib: lrclib, ytm: ytm)
        XCTAssertTrue(best.isSynced)
        XCTAssertEqual(best.source, "ytmusic")
    }

    func testPickBestPrefersLongerPlainLyrics() {
        let lrclib = makeCandidate(
            lines: [
                LyricLine(time: 0, text: "One"),
                LyricLine(time: 0, text: "Two"),
            ],
            isSynced: false
        )
        let ytm = makeCandidate(
            lines: [
                LyricLine(time: 0, text: "One"),
                LyricLine(time: 0, text: "Two"),
                LyricLine(time: 0, text: "Three"),
            ],
            isSynced: false,
            source: "ytmusic"
        )

        let best = LyricsFetcher.pickBest(lrclib: lrclib, ytm: ytm)
        XCTAssertFalse(best.isSynced)
        XCTAssertEqual(best.source, "ytmusic")
        XCTAssertEqual(best.lines.count, 3)
    }

    func testPickBestKeepsLRCLIBWhenLongerPlain() {
        let lrclib = makeCandidate(
            lines: [
                LyricLine(time: 0, text: "One"),
                LyricLine(time: 0, text: "Two"),
                LyricLine(time: 0, text: "Three"),
            ],
            isSynced: false
        )
        let ytm = makeCandidate(
            lines: [LyricLine(time: 0, text: "One")],
            isSynced: false,
            source: "ytmusic"
        )

        let best = LyricsFetcher.pickBest(lrclib: lrclib, ytm: ytm)
        XCTAssertEqual(best.source, "lrclib")
        XCTAssertEqual(best.lines.count, 3)
    }

    func testPickBestUsesYTMWhenLRCLIBEmpty() {
        let lrclib = FetchCandidate.empty
        let ytm = makeCandidate(
            lines: [LyricLine(time: 0, text: "Found on YT")],
            isSynced: false,
            source: "ytmusic"
        )

        let best = LyricsFetcher.pickBest(lrclib: lrclib, ytm: ytm)
        XCTAssertEqual(best.source, "ytmusic")
        XCTAssertEqual(best.lines.count, 1)
    }
}
