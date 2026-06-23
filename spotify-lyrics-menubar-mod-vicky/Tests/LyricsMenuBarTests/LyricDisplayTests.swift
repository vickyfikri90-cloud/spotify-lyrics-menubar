import XCTest
@testable import LyricsMenuBar

final class LyricDisplayTests: XCTestCase {
    func testIsInstrumentalMarkerDetectsNoteSymbol() {
        XCTAssertTrue(LyricDisplay.isInstrumentalMarker("♪"))
        XCTAssertTrue(LyricDisplay.isInstrumentalMarker("♪ ♪ ♪"))
        XCTAssertTrue(LyricDisplay.isInstrumentalMarker("♪♪♪"))
        XCTAssertTrue(LyricDisplay.isInstrumentalMarker("  "))
    }

    func testIsInstrumentalMarkerRejectsVocalText() {
        XCTAssertFalse(LyricDisplay.isInstrumentalMarker("Hello"))
        XCTAssertFalse(LyricDisplay.isInstrumentalMarker("Hello ♪ world"))
    }

    func testCountdownBeforeFirstVocalWithinTenSeconds() {
        let lyrics = [
            LyricLine(time: 15, text: "First vocal"),
        ]
        // 15 seconds remaining — outside 10s window
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 0), "...")
        // 2 seconds remaining — dot countdown
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 13), "● ●")
    }

    func testCountdownMidSongAfterInstrumentalWithinThreeSeconds() {
        let lyrics = [
            LyricLine(time: 0, text: "Hello"),
            LyricLine(time: 10, text: "♪"),
            LyricLine(time: 20, text: "World"),
        ]
        // 5 seconds remaining to next vocal — outside 3s mid-song window
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 15), "...")
        // 2 seconds remaining
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 18), "● ●")
    }

    func testShowsVocalLineWhenActive() {
        let lyrics = [
            LyricLine(time: 0, text: "Hello"),
            LyricLine(time: 10, text: "♪"),
            LyricLine(time: 20, text: "World"),
        ]
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 5), "Hello")
    }

    func testInstrumentalAtStartUsesTenSecondWindow() {
        let lyrics = [
            LyricLine(time: 0, text: "♪"),
            LyricLine(time: 15, text: "First vocal"),
        ]
        // 15 seconds remaining — outside 10s start window
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 0), "...")
        XCTAssertEqual(LyricDisplay.ytmSyncedStatus(lyrics: lyrics, at: 13), "● ●")
    }

    func testStandardSyncedStatusUnchangedForLRCLIB() {
        let lyrics = [
            LyricLine(time: 20, text: "Line one"),
        ]
        XCTAssertEqual(LyricDisplay.syncedStatus(lyrics: lyrics, at: 21, source: "lrclib"), "Line one")
        XCTAssertEqual(LyricDisplay.syncedStatus(lyrics: lyrics, at: 5, source: "lrclib"), "...")
        XCTAssertEqual(LyricDisplay.syncedStatus(lyrics: lyrics, at: 18, source: "lrclib"), "● ●")
    }

    func testCountdownDisplay() {
        XCTAssertEqual(LyricDisplay.countdownDisplay(seconds: 1), "●")
        XCTAssertEqual(LyricDisplay.countdownDisplay(seconds: 2), "● ●")
        XCTAssertEqual(LyricDisplay.countdownDisplay(seconds: 3), "● ● ●")
    }
}
