import XCTest
@testable import LyricsMenuBar

final class LyricsCacheTests: XCTestCase {
    override func tearDown() {
        LyricsCache.removeAll()
        super.tearDown()
    }

    func testCacheKeyUsesNormalizedArtistAndTrack() {
        let key = LyricsCache.cacheKey(track: "Panasea (Live)", artist: "rumahsakit, guest")
        XCTAssertEqual(key, "rumahsakit|panasea")
    }

    func testSaveAndLoadSyncedLyrics() {
        LyricsCache.save(
            track: "Panasea",
            artist: "rumahsakit",
            syncedLyrics: "[00:01.00] Hello world",
            plainLyrics: nil
        )

        let loaded = LyricsCache.load(track: "Panasea", artist: "rumahsakit", duration: 200)
        XCTAssertEqual(loaded?.0.count, 1)
        XCTAssertEqual(loaded?.0.first?.text, "Hello world")
        XCTAssertTrue(loaded?.1 ?? false)
        XCTAssertEqual(LyricsCache.count, 1)
    }

    func testPlainLyricsReturnUntimedLines() {
        LyricsCache.save(
            track: "Song",
            artist: "Artist",
            syncedLyrics: nil,
            plainLyrics: "Line one\nLine two"
        )

        let loaded = LyricsCache.load(track: "Song", artist: "Artist", duration: 100)
        XCTAssertEqual(loaded?.0.count, 2)
        XCTAssertEqual(loaded?.0[0].text, "Line one")
        XCTAssertEqual(loaded?.0[1].text, "Line two")
        XCTAssertEqual(loaded?.0[0].time, 0)
        XCTAssertEqual(loaded?.0[1].time, 0)
        XCTAssertFalse(loaded?.1 ?? true)
    }

    func testRemoveAllClearsCache() {
        LyricsCache.save(track: "A", artist: "B", syncedLyrics: "[00:01.00] Hi", plainLyrics: nil)
        LyricsCache.removeAll()
        XCTAssertEqual(LyricsCache.count, 0)
        XCTAssertNil(LyricsCache.load(track: "A", artist: "B", duration: 120))
    }
}
