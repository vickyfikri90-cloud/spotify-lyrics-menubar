import XCTest
@testable import YTMusicLyrics

final class YTMusicLyricsFetcherTests: XCTestCase {
    func testParseTimedLyrics() throws {
        let json = """
        {
          "contents": {
            "elementRenderer": {
              "newElement": {
                "type": {
                  "componentType": {
                    "model": {
                      "timedLyricsModel": {
                        "lyricsData": {
                          "timedLyricsData": [
                            {
                              "lyricLine": "Today is gonna be the day",
                              "cueRange": {
                                "startTimeMilliseconds": "9200",
                                "endTimeMilliseconds": "10630",
                                "metadata": { "id": "1" }
                              }
                            },
                            {
                              "lyricLine": "That they're gonna throw it back to you",
                              "cueRange": {
                                "startTimeMilliseconds": "10680",
                                "endTimeMilliseconds": "12540",
                                "metadata": { "id": "2" }
                              }
                            }
                          ]
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(YTMusicLyricsFetcher.parseTimedLyrics(from: response))

        XCTAssertTrue(result.isSynced)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].text, "Today is gonna be the day")
        XCTAssertEqual(result.lines[0].time, 9.2, accuracy: 0.001)
        XCTAssertNotNil(result.syncedLRC)
        XCTAssertTrue(result.syncedLRC?.contains("[00:09.20]") == true)
    }

    func testParsePlainLyrics() throws {
        let json = """
        {
          "contents": {
            "sectionListRenderer": {
              "contents": [
                {
                  "musicDescriptionShelfRenderer": {
                    "description": {
                      "runs": [
                        { "text": "Line one\\nLine two" }
                      ]
                    }
                  }
                }
              ]
            }
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(YTMusicLyricsFetcher.parsePlainLyrics(from: response))

        XCTAssertFalse(result.isSynced)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines[0].text, "Line one")
        XCTAssertEqual(result.lines[1].text, "Line two")
    }

    func testExtractLyricsBrowseId() throws {
        let json = """
        {
          "contents": {
            "singleColumnMusicWatchNextResultsRenderer": {
              "tabbedRenderer": {
                "watchNextTabbedResultsRenderer": {
                  "tabs": [
                    {
                      "tabRenderer": {
                        "title": "Related",
                        "endpoint": {
                          "browseEndpoint": {
                            "browseId": "MPLRD123",
                            "browseEndpointContextSupportedConfigs": {
                              "browseEndpointContextMusicConfig": {
                                "pageType": "MUSIC_PAGE_TYPE_TRACK_RELATED"
                              }
                            }
                          }
                        }
                      }
                    },
                    {
                      "tabRenderer": {
                        "title": "Lyrics",
                        "endpoint": {
                          "browseEndpoint": {
                            "browseId": "MPLYt_HNNclO0Ddoc-17",
                            "browseEndpointContextSupportedConfigs": {
                              "browseEndpointContextMusicConfig": {
                                "pageType": "MUSIC_PAGE_TYPE_TRACK_LYRICS"
                              }
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let browseId = YTMusicLyricsFetcher.extractLyricsBrowseId(from: response)
        XCTAssertEqual(browseId, "MPLYt_HNNclO0Ddoc-17")
    }

    func testLinesToLRC() {
        let lines = [
            YTMusicLyricLine(time: 92.0, text: "Hello"),
            YTMusicLyricLine(time: 125.5, text: "World"),
        ]
        let lrc = YTMusicLyricsFetcher.linesToLRC(lines)
        XCTAssertTrue(lrc.contains("[01:32.00] Hello"))
        XCTAssertTrue(lrc.contains("[02:05.50] World"))
    }
}

final class YTMusicSearchTests: XCTestCase {
    func testSelectBestMatchPrefersExactTitleAndArtist() {
        let results = [
            YTMusicSearchResult(videoId: "aaa", title: "Wonderwall", artists: ["Oasis"], durationSeconds: 258),
            YTMusicSearchResult(videoId: "bbb", title: "Wonderwall (Live)", artists: ["Oasis"], durationSeconds: 300),
        ]
        let match = YTMusicSearch.selectBestMatch(from: results, track: "Wonderwall", artist: "Oasis")
        XCTAssertEqual(match?.videoId, "aaa")
    }

    func testSelectBestMatchFallsBackToFirstResult() {
        let results = [
            YTMusicSearchResult(videoId: "zzz", title: "Different Song", artists: ["Other Artist"], durationSeconds: 200),
        ]
        let match = YTMusicSearch.selectBestMatch(from: results, track: "Wonderwall", artist: "Oasis")
        XCTAssertEqual(match?.videoId, "zzz")
    }
}
